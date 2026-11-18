import 'package:postgres/postgres.dart';

import 'postgres_connection.dart';

/// Atomically records an authenticated, closed MT5 deal and calculates its
/// performance fee. Callers must resolve the license to this account first.
class PostgresProfitShareRepository {
  final PostgresPool pool;

  PostgresProfitShareRepository(this.pool);

  /// Resolves a license credential to its registered, active MT5 account.
  /// The account ID is deliberately derived server-side, never accepted from EA.
  Future<Map<String, String>?> resolveLicensedAccount({
    required String licenseKey,
    required String brokerAccountNumber,
    required String brokerServer,
  }) async {
    if (licenseKey.trim().isEmpty ||
        brokerAccountNumber.trim().isEmpty ||
        brokerServer.trim().isEmpty) {
      return null;
    }
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT ta.id, ta.currency, ta.environment '
        'FROM bot_licenses bl '
        'JOIN trading_accounts ta ON ta.id = bl.trading_account_id '
        'WHERE bl.license_key = @license_key '
        "AND bl.status = 'active' "
        'AND (bl.expires_at IS NULL OR bl.expires_at > NOW()) '
        "AND ta.status = 'active' "
        'AND ta.broker_account_number = @account_number '
        'AND ta.broker_server = @broker_server '
        'LIMIT 1',
      ),
      parameters: {
        'license_key': licenseKey,
        'account_number': brokerAccountNumber,
        'broker_server': brokerServer,
      },
    );
    if (result.isEmpty || result.first[1] == null) return null;
    return {
      'tradingAccountId': result.first[0].toString(),
      'currency': result.first[1].toString().trim(),
      'environment': result.first[2].toString(),
    };
  }

  /// Returns null when the broker deal was already recorded.
  /// Monetary values must be decimal strings, never binary floating-point.
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
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
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
      final account = await tx.execute(
        Sql.named(
          'SELECT currency, status FROM trading_accounts '
          'WHERE id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      if (account.isEmpty || account.first[1]?.toString() != 'active') {
        throw StateError('Trading account not found or inactive.');
      }
      final accountCurrency = account.first[0]?.toString().trim();
      if (accountCurrency != null &&
          accountCurrency.isNotEmpty &&
          accountCurrency != currency) {
        throw StateError('Deal currency does not match registered account currency.');
      }

      // Serialize all account deal ingestion before inserting a new deal.
      await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_account_state (trading_account_id) '
          'VALUES (@account_id::uuid) ON CONFLICT (trading_account_id) DO NOTHING',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      final stateResult = await tx.execute(
        Sql.named(
          'SELECT cumulative_net_profit, high_water_mark '
          'FROM profit_share_account_state '
          'WHERE trading_account_id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      final state = stateResult.first;

      final inserted = await tx.execute(
        Sql.named(
          'INSERT INTO realized_trade_deals '
          '(trading_account_id, broker_deal_id, symbol, deal_time, currency, '
          'profit, commission, swap, broker_fee, net_profit, payload_hash) '
          'VALUES (@account_id::uuid, @deal_id, @symbol, @deal_time, @currency, '
          '@profit::numeric, @commission::numeric, @swap::numeric, @broker_fee::numeric, '
          '(@profit::numeric + @commission::numeric + @swap::numeric + @broker_fee::numeric), '
          '@payload_hash) '
          'ON CONFLICT (trading_account_id, broker_deal_id) DO NOTHING RETURNING id',
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
      if (inserted.isEmpty) return null;
      final dealId = inserted.first[0].toString();

      // HWM is path-dependent. The EA must submit closed deals chronologically.
      final latest = await tx.execute(
        Sql.named(
          'SELECT deal_time FROM realized_trade_deals '
          'WHERE trading_account_id = @account_id::uuid AND id <> @deal_id::uuid '
          'ORDER BY deal_time DESC, received_at DESC LIMIT 1',
        ),
        parameters: {'account_id': tradingAccountId, 'deal_id': dealId},
      );
      if (latest.isNotEmpty &&
          dealTime.toUtc().isBefore((latest.first[0] as DateTime).toUtc())) {
        throw StateError('Out-of-order deal. Reconcile broker history chronologically before retrying.');
      }

      final policy = await tx.execute(
        Sql.named(
          'SELECT id, share_rate FROM profit_share_policies '
          'WHERE is_active = TRUE AND effective_from <= @deal_time '
          'ORDER BY effective_from DESC LIMIT 1',
        ),
        parameters: {'deal_time': dealTime.toUtc()},
      );
      if (policy.isEmpty) {
        // Keep the deal ledger auditable, but never accrue without an active policy.
        return {
          'dealId': dealId,
          'currency': currency,
          'feeEnabled': false,
          'reason': 'NO_ACTIVE_POLICY',
        };
      }

      final policyId = policy.first[0].toString();
      final rate = policy.first[1].toString();
      final cumulativeBefore = state[0].toString();
      final hwmBefore = state[1].toString();
      final calcResult = await tx.execute(
        Sql.named(
          'WITH calc_values AS ('
          ' SELECT (@cumulative_before::numeric + '
          ' (SELECT net_profit FROM realized_trade_deals WHERE id = @deal_id::uuid)) AS cumulative_after, '
          ' @hwm_before::numeric AS hwm_before, @rate::numeric AS rate'
          ') '
          'SELECT cumulative_after, hwm_before, '
          ' GREATEST(0, cumulative_after - hwm_before) AS eligible_profit, '
          ' ROUND(GREATEST(0, cumulative_after - hwm_before) * rate, '
          ' @minor_units::int) AS fee_amount, '
          ' GREATEST(hwm_before, cumulative_after) AS hwm_after '
          'FROM calc_values',
        ),
        parameters: {
          'cumulative_before': cumulativeBefore,
          'hwm_before': hwmBefore,
          'rate': rate,
          'deal_id': dealId,
          'minor_units': currencyMinorUnits,
        },
      );
      final calc = calcResult.first;
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

      final accrual = await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_accruals '
          '(trading_account_id, deal_id, policy_id, cumulative_net_profit, '
          'hwm_before, hwm_after, eligible_profit, share_rate, fee_amount, currency) '
          'VALUES (@account_id::uuid, @deal_id::uuid, @policy_id::uuid, '
          '@cumulative::numeric, @hwm_before::numeric, @hwm_after::numeric, '
          '@eligible::numeric, @rate::numeric, @fee::numeric, @currency) RETURNING id',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'deal_id': dealId,
          'policy_id': policyId,
          'cumulative': cumulativeAfter,
          'hwm_before': hwmBefore,
          'hwm_after': hwmAfter,
          'eligible': eligibleProfit,
          'rate': rate,
          'fee': feeAmount,
          'currency': currency,
        },
      );

      return {
        'dealId': dealId,
        'accrualId': accrual.first[0].toString(),
        'currency': currency,
        'feeEnabled': true,
        'cumulativeNetProfit': cumulativeAfter,
        'highWaterMark': hwmAfter,
        'eligibleProfit': eligibleProfit,
        'shareRate': rate,
        'feeAmount': feeAmount,
      };
    });
  }

  /// Builds a draft monthly statement from accrued, unbilled fees.
  ///
  /// This operation is intentionally gated by an explicit reconciliation
  /// assertion from the caller. It does not issue an invoice, mark accruals
  /// invoiced, or collect money. The caller must only pass true after the
  /// broker's complete closed-deal history for the period has been reconciled.
  ///
  /// Repeated calls for the same account and period return the existing
  /// statement without adding duplicate items.
  Future<Map<String, Object?>> generateMonthlyStatement({
    required String tradingAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required bool brokerHistoryReconciled,
  }) async {
    if (!brokerHistoryReconciled) {
      throw StateError(
        'Broker history must be reconciled before generating a statement.',
      );
    }
    final start = DateTime.utc(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final end = DateTime.utc(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
    );
    if (!end.isAfter(start)) {
      throw ArgumentError('periodEnd must be after periodStart.');
    }
    if (start.day != 1 ||
        end.day != 1 ||
        (end.year == start.year && end.month != start.month + 1) ||
        (end.year == start.year + 1 &&
            !(start.month == 12 && end.month == 1)) ||
        end.difference(start).inDays < 28 ||
        end.difference(start).inDays > 31) {
      throw ArgumentError(
        'Statements must cover one complete calendar month.',
      );
    }

    final conn = await pool.connection;
    return conn.runTx((tx) async {
      // Lock the account to serialize statement generation with other
      // account-level financial operations.
      final accountResult = await tx.execute(
        Sql.named(
          'SELECT currency, status FROM trading_accounts '
          'WHERE id = @account_id::uuid FOR UPDATE',
        ),
        parameters: {'account_id': tradingAccountId},
      );
      if (accountResult.isEmpty ||
          accountResult.first[1]?.toString() != 'active') {
        throw StateError('Trading account not found or inactive.');
      }
      final currency = accountResult.first[0]?.toString().trim();
      if (currency == null || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        throw StateError('Trading account has no valid ISO currency.');
      }

      // Idempotency: a statement is unique for account + calendar period.
      final inserted = await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_statements '
          '(trading_account_id, period_start, period_end, currency, status) '
          'VALUES (@account_id::uuid, @period_start::date, @period_end::date, '
          '@currency, \'draft\') '
          'ON CONFLICT (trading_account_id, period_start, period_end) '
          'DO NOTHING RETURNING id',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'period_start': start,
          'period_end': end,
          'currency': currency,
        },
      );

      final statementResult = await tx.execute(
        Sql.named(
          'SELECT id, status, currency, eligible_profit, fee_amount '
          'FROM profit_share_statements '
          'WHERE trading_account_id = @account_id::uuid '
          'AND period_start = @period_start::date '
          'AND period_end = @period_end::date '
          'FOR UPDATE',
        ),
        parameters: {
          'account_id': tradingAccountId,
          'period_start': start,
          'period_end': end,
        },
      );
      if (statementResult.isEmpty) {
        throw StateError('Unable to create or retrieve monthly statement.');
      }
      final statement = statementResult.first;
      final statementId = statement[0].toString();

      // Only a newly created draft is populated. Existing statements are
      // immutable through this method; corrections require an adjustment flow.
      if (inserted.isNotEmpty) {
        await tx.execute(
          Sql.named(
            'INSERT INTO profit_share_statement_items '
            '(statement_id, accrual_id, eligible_profit, fee_amount, currency) '
            'SELECT @statement_id::uuid, a.id, a.eligible_profit, '
            'a.fee_amount, a.currency '
            'FROM profit_share_accruals a '
            'JOIN realized_trade_deals d ON d.id = a.deal_id '
            'WHERE a.trading_account_id = @account_id::uuid '
            'AND d.deal_time >= @period_start::date '
            'AND d.deal_time < @period_end::date '
            "AND a.status = 'accrued' "
            'AND a.fee_amount > 0 '
            'AND a.currency = @currency '
            'ORDER BY d.deal_time, d.broker_deal_id',
          ),
          parameters: {
            'statement_id': statementId,
            'account_id': tradingAccountId,
            'period_start': start,
            'period_end': end,
            'currency': currency,
          },
        );

        // An empty-fee month is represented by a zero-value statement for
        // auditability. It will not produce an invoice.
        await tx.execute(
          Sql.named(
            'UPDATE profit_share_statements SET '
            'eligible_profit = COALESCE(('
            ' SELECT SUM(eligible_profit) FROM profit_share_statement_items '
            ' WHERE statement_id = @statement_id::uuid'
            '), 0), '
            'fee_amount = COALESCE(('
            ' SELECT SUM(fee_amount) FROM profit_share_statement_items '
            ' WHERE statement_id = @statement_id::uuid'
            '), 0) '
            'WHERE id = @statement_id::uuid',
          ),
          parameters: {'statement_id': statementId},
        );
      }

      final refreshed = await tx.execute(
        Sql.named(
          'SELECT id, status, currency, eligible_profit, fee_amount '
          'FROM profit_share_statements WHERE id = @statement_id::uuid',
        ),
        parameters: {'statement_id': statementId},
      );
      final row = refreshed.first;
      final itemCount = await tx.execute(
        Sql.named(
          'SELECT COUNT(*) FROM profit_share_statement_items '
          'WHERE statement_id = @statement_id::uuid',
        ),
        parameters: {'statement_id': statementId},
      );
      return {
        'statementId': row[0].toString(),
        'status': row[1].toString(),
        'currency': row[2].toString().trim(),
        'eligibleProfit': row[3].toString(),
        'feeAmount': row[4].toString(),
        'itemCount': int.parse(itemCount.first[0].toString()),
        'created': inserted.isNotEmpty,
      };
    });
  }


  /// Finalizes a reconciled draft statement and issues its invoice atomically.
  ///
  /// A zero-fee statement is finalized without creating an invoice. Positive
  /// fee statements create one issued invoice and copy every statement item.
  /// Accrual status changes to invoiced in the same database transaction.
  Future<Map<String, Object?>> finalizeStatementAndIssueInvoice({
    required String statementId,
    int paymentDueDays = 14,
  }) async {
    if (paymentDueDays < 1 || paymentDueDays > 60) {
      throw ArgumentError.value(
        paymentDueDays,
        'paymentDueDays',
        'Must be between 1 and 60 days.',
      );
    }
    final conn = await pool.connection;
    return conn.runTx((tx) async {
      final statementResult = await tx.execute(
        Sql.named(
          'SELECT s.id, s.trading_account_id, s.status, s.currency, '
          's.eligible_profit, s.fee_amount, ta.status '
          'FROM profit_share_statements s '
          'JOIN trading_accounts ta ON ta.id = s.trading_account_id '
          'WHERE s.id = @statement_id::uuid '
          'FOR UPDATE OF s, ta',
        ),
        parameters: {'statement_id': statementId},
      );
      if (statementResult.isEmpty) {
        throw StateError('Statement not found.');
      }
      final row = statementResult.first;
      final accountId = row[1].toString();
      final status = row[2].toString();
      final currency = row[3].toString().trim();
      final feeAmount = row[5].toString();

      if (row[6]?.toString() != 'active') {
        throw StateError('Trading account is not active.');
      }
      if (status != 'draft') {
        throw StateError('Only draft statements can be finalized.');
      }
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        throw StateError('Statement currency is invalid.');
      }

      final totals = await tx.execute(
        Sql.named(
          'SELECT COUNT(*), COALESCE(SUM(eligible_profit), 0), '
          'COALESCE(SUM(fee_amount), 0), '
          'COUNT(*) FILTER (WHERE currency <> @currency) '
          'FROM profit_share_statement_items '
          'WHERE statement_id = @statement_id::uuid',
        ),
        parameters: {
          'statement_id': statementId,
          'currency': currency,
        },
      );
      final total = totals.first;
      final itemCount = int.parse(total[0].toString());
      final itemEligible = total[1].toString();
      final itemFees = total[2].toString();
      final mismatchedCurrencies = int.parse(total[3].toString());

      if (mismatchedCurrencies != 0) {
        throw StateError('Statement contains mixed currencies.');
      }
      if (itemFees != feeAmount) {
        // Numeric string formatting can differ (e.g. 1.0 vs 1.000).
        final compare = await tx.execute(
          Sql.named(
            'SELECT (@stored::numeric = @calculated::numeric)',
          ),
          parameters: {'stored': feeAmount, 'calculated': itemFees},
        );
        if (compare.first[0] != true) {
          throw StateError('Statement total does not match its items.');
        }
      }
      final eligibleCompare = await tx.execute(
        Sql.named(
          'SELECT (eligible_profit = @calculated::numeric) '
          'FROM profit_share_statements WHERE id = @statement_id::uuid',
        ),
        parameters: {
          'calculated': itemEligible,
          'statement_id': statementId,
        },
      );
      if (eligibleCompare.first[0] != true) {
        throw StateError('Statement eligible-profit total does not match its items.');
      }

      final unavailableAccruals = await tx.execute(
        Sql.named(
          'SELECT COUNT(*) '
          'FROM profit_share_statement_items si '
          'JOIN profit_share_accruals a ON a.id = si.accrual_id '
          'WHERE si.statement_id = @statement_id::uuid '
          "AND (a.status <> 'accrued' OR a.trading_account_id <> @account_id::uuid "
          'OR a.currency <> @currency)',
        ),
        parameters: {
          'statement_id': statementId,
          'account_id': accountId,
          'currency': currency,
        },
      );
      if (int.parse(unavailableAccruals.first[0].toString()) != 0) {
        throw StateError('One or more accruals are no longer billable.');
      }

      if (itemCount == 0 || itemFees == '0' || itemFees == '0.0') {
        // Also guard against zero values formatted with more decimal places.
        final zeroCheck = await tx.execute(
          Sql.named('SELECT (@amount::numeric = 0)'),
          parameters: {'amount': itemFees},
        );
        if (zeroCheck.first[0] == true) {
          await tx.execute(
            Sql.named(
              'UPDATE profit_share_statements SET status = \'finalized\', '
              'finalized_at = NOW() WHERE id = @statement_id::uuid',
            ),
            parameters: {'statement_id': statementId},
          );
          return {
            'statementId': statementId,
            'status': 'finalized',
            'invoiceCreated': false,
            'itemCount': itemCount,
            'currency': currency,
            'feeAmount': itemFees,
          };
        }
      }

      // UUID suffix prevents collisions without requiring a mutable sequence.
      final invoiceNumberResult = await tx.execute(
        Sql.named(
          "SELECT 'TNX-' || TO_CHAR(CURRENT_DATE, 'YYYYMM') || '-' || "
          "UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', '') FROM 1 FOR 12))",
        ),
      );
      final invoiceNumber = invoiceNumberResult.first[0].toString();

      final invoice = await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_invoices '
          '(statement_id, trading_account_id, invoice_number, amount_due, '
          'currency, status, issued_at, due_at) '
          'VALUES (@statement_id::uuid, @account_id::uuid, @invoice_number, '
          '@amount::numeric, @currency, \'issued\', NOW(), '
          'NOW() + (@due_days::int * INTERVAL \'1 day\')) '
          'RETURNING id, invoice_number, amount_due, currency, status, due_at',
        ),
        parameters: {
          'statement_id': statementId,
          'account_id': accountId,
          'invoice_number': invoiceNumber,
          'amount': itemFees,
          'currency': currency,
          'due_days': paymentDueDays,
        },
      );
      final invoiceId = invoice.first[0].toString();

      await tx.execute(
        Sql.named(
          'INSERT INTO profit_share_invoice_items '
          '(invoice_id, accrual_id, amount, currency) '
          'SELECT @invoice_id::uuid, si.accrual_id, si.fee_amount, si.currency '
          'FROM profit_share_statement_items si '
          'WHERE si.statement_id = @statement_id::uuid '
          'AND si.fee_amount > 0',
        ),
        parameters: {
          'invoice_id': invoiceId,
          'statement_id': statementId,
        },
      );

      final invoiceTotal = await tx.execute(
        Sql.named(
          'SELECT COALESCE(SUM(amount), 0) FROM profit_share_invoice_items '
          'WHERE invoice_id = @invoice_id::uuid',
        ),
        parameters: {'invoice_id': invoiceId},
      );
      final invoiceMatches = await tx.execute(
        Sql.named(
          'SELECT (@invoice_total::numeric = amount_due) '
          'FROM profit_share_invoices WHERE id = @invoice_id::uuid',
        ),
        parameters: {
          'invoice_total': invoiceTotal.first[0].toString(),
          'invoice_id': invoiceId,
        },
      );
      if (invoiceMatches.first[0] != true) {
        throw StateError('Invoice item total does not match amount due.');
      }

      await tx.execute(
        Sql.named(
          'UPDATE profit_share_accruals a SET status = \'invoiced\' '
          'FROM profit_share_statement_items si '
          'WHERE si.statement_id = @statement_id::uuid '
          'AND si.accrual_id = a.id '
          "AND a.status = 'accrued'",
        ),
        parameters: {'statement_id': statementId},
      );
      await tx.execute(
        Sql.named(
          'UPDATE profit_share_statements SET status = \'finalized\', '
          'finalized_at = NOW() WHERE id = @statement_id::uuid',
        ),
        parameters: {'statement_id': statementId},
      );

      final createdInvoice = invoice.first;
      return {
        'statementId': statementId,
        'status': 'finalized',
        'invoiceCreated': true,
        'invoiceId': invoiceId,
        'invoiceNumber': createdInvoice[1].toString(),
        'amountDue': createdInvoice[2].toString(),
        'currency': createdInvoice[3].toString().trim(),
        'invoiceStatus': createdInvoice[4].toString(),
        'dueAt': (createdInvoice[5] as DateTime).toUtc().toIso8601String(),
        'itemCount': itemCount,
      };
    });
  }

}
