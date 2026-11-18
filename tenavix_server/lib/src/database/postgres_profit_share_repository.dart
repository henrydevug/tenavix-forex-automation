import 'package:postgres/postgres.dart';

import 'postgres_connection.dart';

/// Persists a normalized, already-authenticated closed MT5 deal and accrues
/// the performance fee atomically. Broker authentication and account ownership
/// must be verified before this repository is called.
class PostgresProfitShareRepository {
  final PostgresPool pool;

  PostgresProfitShareRepository(this.pool);

  /// Returns null for an already-processed broker deal.
  ///
  /// Monetary inputs are decimal strings in the MT5 account deposit currency.
  /// Never pass Dart double values for money.
  Future<Map<String, Object?>?> recordClosedDeal({
    required String tradingAccountId,
    required String brokerDealId,
    required String symbol,
    required DateTime dealTime,
    required String currency,
    required int currencyMinorUnits,
    required String profit,
    String commission = '0',
    String swap = '0',
    String brokerFee = '0',
    String? payloadHash,
  }) async {
    if (brokerDealId.trim().isEmpty || symbol.trim().isEmpty) {
      throw ArgumentError('Broker deal ID and symbol are required.');
    }
    if (!RegExp(r'^[A-Z]{3}
      throw ArgumentError.value(currency, 'currency', 'Expected ISO 4217 code.');
    }
    if (currencyMinorUnits < 0 || currencyMinorUnits > 8) {
      throw ArgumentError.value(currencyMinorUnits, 'currencyMinorUnits');
    }
    for (final value in [profit, commission, swap, brokerFee]) {
      if (!RegExp(r'^-?\d+(\.\d{1,8})?$').hasMatch(value)) {
        throw ArgumentError.value(value, 'money', 'Use a decimal string with up to 8 places.');
      }
    }
    if (payloadHash != null &&
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(payloadHash)) {
      throw ArgumentError.value(payloadHash, 'payloadHash', 'Expected SHA-256 hex.');
    }

    final conn = await pool.connection;
    return conn.runTx((tx) async {
      // Validate the account exists and obtain its registered deposit currency.
      final accountResult = await tx.execute(
        Sql.named(
          'SELECT currency FROM trading_accounts WHERE id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      if (accountResult.isEmpty) {
        throw StateError('Trading account not found.');
      }
      final accountCurrency = accountResult.first[0]?.toString().trim();
      if (accountCurrency != null &&
          accountCurrency.isNotEmpty &&
          accountCurrency != currency) {
        throw StateError('Deal currency does not match registered account currency.');
      }

      // Idempotency is enforced by the database unique constraint.
      final dealResult = await tx.execute(
        Sql.named(
          'INSERT INTO realized_trade_deals '
          '(trading_account_id, broker_deal_id, symbol, deal_time, currency, '
          'profit, commission, swap, broker_fee, net_profit, payload_hash) '
          'VALUES (@account_id::uuid, @deal_id, @symbol, @deal_time, @currency, '
          '@profit::numeric, @commission::numeric, @swap::numeric, @broker_fee::numeric, '
          '(@profit::numeric + @commission::numeric + @swap::numeric + @broker_fee::numeric), '
          '@payload_hash) '
          'ON CONFLICT (trading_account_id, broker_deal_id) DO NOTHING '
          'RETURNING id',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'deal_id': brokerDealId,
          'symbol': symbol,
          'deal_time': dealTime.toUtc(),
          'currency': currency,
          'profit': profit,
          'commission': commission,
          'swap': swap,
          'broker_fee': brokerFee,
          'payload_hash': payloadHash,
        },
      );
      if (dealResult.isEmpty) return null;
      final dealId = dealResult.first[0].toString();

      // Ensure a state row exists, then serialize calculations for this account.
      await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_account_state (trading_account_id) '
          'VALUES (@account_id::uuid) ON CONFLICT (trading_account_id) DO NOTHING',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      final stateResult = await tx.execute(
        Sql.named(
          'SELECT cumulative_net_profit, high_water_mark, total_fee_accrued '
          'FROM profit_share_account_state '
          'WHERE trading_account_id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      final state = stateResult.first;
      final cumulativeBefore = state[0].toString();
      final hwmBefore = state[1].toString();

      final policyResult = await tx.execute(
        Sql.named(
          'SELECT id, share_rate FROM profit_share_policies '
          'WHERE is_active = TRUE ORDER BY effective_from DESC LIMIT 1',
        ),
      );
      if (policyResult.isEmpty) {
        throw StateError('No active performance-fee policy is configured.');
      }
      final policyId = policyResult.first[0].toString();
      final shareRate = policyResult.first[1].toString();

      // NUMERIC arithmetic and ROUND happen inside PostgreSQL, avoiding doubles.
      final calculation = await tx.execute(
        Sql.named(
          'WITH calc_values AS ('
          ' SELECT (@cumulative_before::numeric + '
          ' (SELECT net_profit FROM realized_trade_deals WHERE id = @deal_id::uuid)) AS cumulative_after, '
          ' @hwm_before::numeric AS hwm_before, @share_rate::numeric AS rate'
          ') '
          'SELECT cumulative_after, hwm_before, '
          ' GREATEST(0, cumulative_after - hwm_before) AS eligible_profit, '
          ' ROUND(GREATEST(0, cumulative_after - hwm_before) * rate, '
          '       @currency_minor_units::int) AS fee_amount, ',
          ' GREATEST(hwm_before, cumulative_after) AS hwm_after '
          'FROM calc_values',
        ),
        parameters: {
          'cumulative_before': cumulativeBefore,
          'hwm_before': hwmBefore,
          'share_rate': shareRate,
          'deal_id': dealId,
          'currency_minor_units': currencyMinorUnits,
        },
      );
      final calc = calculation.first;
      final cumulativeAfter = calc[0].toString();
      final eligibleProfit = calc[2].toString();
      final feeAmount = calc[3].toString();
      final hwmAfter = calc[4].toString();

      await tx.execute(
        Sql.named(
          'UPDATE profit_share_account_state SET '
          'cumulative_net_profit = @cumulative::numeric, '
          'high_water_mark = @hwm::numeric, '
          'total_fee_accrued = total_fee_accrued + @fee::numeric, '
          'updated_at = NOW() WHERE trading_account_id = @account_id::uuid',
        ),
        parameters: {
          'cumulative': cumulativeAfter,
          'hwm': hwmAfter,
          'fee': feeAmount,
          'account_id': tradingAccountId,
        },
      );

      final accrualResult = await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_accruals '
          '(trading_account_id, deal_id, policy_id, cumulative_net_profit, '
          'hwm_before, hwm_after, eligible_profit, share_rate, fee_amount, currency) '
          'VALUES (@account_id::uuid, @deal_id::uuid, @policy_id::uuid, '
          '@cumulative::numeric, @hwm_before::numeric, @hwm_after::numeric, '
          '@eligible::numeric, @rate::numeric, @fee::numeric, @currency) '
          'RETURNING id',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'deal_id': dealId,
          'policy_id': policyId,
          'cumulative': cumulativeAfter,
          'hwm_before': hwmBefore,
          'hwm_after': hwmAfter,
          'eligible': eligibleProfit,
          'rate': shareRate,
          'fee': feeAmount,
          'currency': currency,
        },
      );

      return {
        'dealId': dealId,
        'accrualId': accrualResult.first[0].toString(),
        'currency': currency,
        'cumulativeNetProfit': cumulativeAfter,
        'highWaterMark': hwmAfter,
        'eligibleProfit': eligibleProfit,
        'shareRate': shareRate,
        'feeAmount': feeAmount,
      };
    });
  }
}
).hasMatch(currency)) {
      throw ArgumentError.value(currency, 'currency', 'Expected ISO 4217 code.');
    }
    for (final value in [profit, commission, swap, brokerFee]) {
      if (!RegExp(r'^-?\d+(\.\d{1,8})?$').hasMatch(value)) {
        throw ArgumentError.value(value, 'money', 'Use a decimal string with up to 8 places.');
      }
    }
    if (payloadHash != null &&
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(payloadHash)) {
      throw ArgumentError.value(payloadHash, 'payloadHash', 'Expected SHA-256 hex.');
    }

    final conn = await pool.connection;
    return conn.runTx((tx) async {
      // Validate the account exists and obtain its registered deposit currency.
      final accountResult = await tx.execute(
        Sql.named(
          'SELECT currency FROM trading_accounts WHERE id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      if (accountResult.isEmpty) {
        throw StateError('Trading account not found.');
      }
      final accountCurrency = accountResult.first[0]?.toString().trim();
      if (accountCurrency != null &&
          accountCurrency.isNotEmpty &&
          accountCurrency != currency) {
        throw StateError('Deal currency does not match registered account currency.');
      }

      // Idempotency is enforced by the database unique constraint.
      final dealResult = await tx.execute(
        Sql.named(
          'INSERT INTO realized_trade_deals '
          '(trading_account_id, broker_deal_id, symbol, deal_time, currency, '
          'profit, commission, swap, broker_fee, net_profit, payload_hash) '
          'VALUES (@account_id::uuid, @deal_id, @symbol, @deal_time, @currency, '
          '@profit::numeric, @commission::numeric, @swap::numeric, @broker_fee::numeric, '
          '(@profit::numeric + @commission::numeric + @swap::numeric + @broker_fee::numeric), '
          '@payload_hash) '
          'ON CONFLICT (trading_account_id, broker_deal_id) DO NOTHING '
          'RETURNING id',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'deal_id': brokerDealId,
          'symbol': symbol,
          'deal_time': dealTime.toUtc(),
          'currency': currency,
          'profit': profit,
          'commission': commission,
          'swap': swap,
          'broker_fee': brokerFee,
          'payload_hash': payloadHash,
        },
      );
      if (dealResult.isEmpty) return null;
      final dealId = dealResult.first[0].toString();

      // Ensure a state row exists, then serialize calculations for this account.
      await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_account_state (trading_account_id) '
          'VALUES (@account_id::uuid) ON CONFLICT (trading_account_id) DO NOTHING',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      final stateResult = await tx.execute(
        Sql.named(
          'SELECT cumulative_net_profit, high_water_mark, total_fee_accrued '
          'FROM profit_share_account_state '
          'WHERE trading_account_id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      final state = stateResult.first;
      final cumulativeBefore = state[0].toString();
      final hwmBefore = state[1].toString();

      final policyResult = await tx.execute(
        Sql.named(
          'SELECT id, share_rate FROM profit_share_policies '
          'WHERE is_active = TRUE ORDER BY effective_from DESC LIMIT 1',
        ),
      );
      if (policyResult.isEmpty) {
        throw StateError('No active performance-fee policy is configured.');
      }
      final policyId = policyResult.first[0].toString();
      final shareRate = policyResult.first[1].toString();

      // NUMERIC arithmetic and ROUND happen inside PostgreSQL, avoiding doubles.
      final calculation = await tx.execute(
        Sql.named(
          'WITH values AS ('
          ' SELECT (@cumulative_before::numeric + '
          ' (SELECT net_profit FROM realized_trade_deals WHERE id = @deal_id::uuid)) AS cumulative_after, '
          ' @hwm_before::numeric AS hwm_before, @share_rate::numeric AS rate'
          ') '
          'SELECT cumulative_after, hwm_before, '
          ' GREATEST(0, cumulative_after - hwm_before) AS eligible_profit, '
          ' ROUND(GREATEST(0, cumulative_after - hwm_before) * rate, '
          '       CASE WHEN @currency IN (\'JPY\', \'KRW\') THEN 0 ELSE 2 END) AS fee_amount, '
          ' GREATEST(hwm_before, cumulative_after) AS hwm_after '
          'FROM values',
        ),
        parameters: {
          'cumulative_before': cumulativeBefore,
          'hwm_before': hwmBefore,
          'share_rate': shareRate,
          'deal_id': dealId,
          'currency_minor_units': currencyMinorUnits,
        },
      );
      final calc = calculation.first;
      final cumulativeAfter = calc[0].toString();
      final eligibleProfit = calc[2].toString();
      final feeAmount = calc[3].toString();
      final hwmAfter = calc[4].toString();

      await tx.execute(
        Sql.named(
          'UPDATE profit_share_account_state SET '
          'cumulative_net_profit = @cumulative::numeric, '
          'high_water_mark = @hwm::numeric, '
          'total_fee_accrued = total_fee_accrued + @fee::numeric, '
          'updated_at = NOW() WHERE trading_account_id = @account_id::uuid',
        ),
        parameters: {
          'cumulative': cumulativeAfter,
          'hwm': hwmAfter,
          'fee': feeAmount,
          'account_id': tradingAccountId,
        },
      );

      final accrualResult = await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_accruals '
          '(trading_account_id, deal_id, policy_id, cumulative_net_profit, '
          'hwm_before, hwm_after, eligible_profit, share_rate, fee_amount, currency) '
          'VALUES (@account_id::uuid, @deal_id::uuid, @policy_id::uuid, '
          '@cumulative::numeric, @hwm_before::numeric, @hwm_after::numeric, '
          '@eligible::numeric, @rate::numeric, @fee::numeric, @currency) '
          'RETURNING id',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'deal_id': dealId,
          'policy_id': policyId,
          'cumulative': cumulativeAfter,
          'hwm_before': hwmBefore,
          'hwm_after': hwmAfter,
          'eligible': eligibleProfit,
          'rate': shareRate,
          'fee': feeAmount,
          'currency': currency,
        },
      );

      return {
        'dealId': dealId,
        'accrualId': accrualResult.first[0].toString(),
        'currency': currency,
        'cumulativeNetProfit': cumulativeAfter,
        'highWaterMark': hwmAfter,
        'eligibleProfit': eligibleProfit,
        'shareRate': shareRate,
        'feeAmount': feeAmount,
      };
    });
  }
}
