import 'package:postgres/postgres.dart';
import '../accounts/account_service.dart';
import '../accounts/trading_account.dart';
import '../licensing/bot_license.dart';
import '../subscriptions/subscription.dart';
import '../common/types.dart';
import 'postgres_connection.dart';

class PostgresTradingAccountRepository implements TradingAccountRepository {
  final PostgresPool pool;
  PostgresTradingAccountRepository(this.pool);

  @override
  Future<TradingAccount?> findById(String id) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, user_id, broker_account_number, broker_server, account_name, '
        'environment, status, currency, created_at, updated_at '
        'FROM trading_accounts WHERE id = @id::uuid LIMIT 1',
      ),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _map(result.first);
  }

  @override
  Future<List<TradingAccount>> findByUserId(String userId) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, user_id, broker_account_number, broker_server, account_name, '
        'environment, status, currency, created_at, updated_at '
        'FROM trading_accounts WHERE user_id = @user_id::uuid ORDER BY created_at',
      ),
      parameters: {'user_id': userId},
    );
    return result.map(_map).toList();
  }

  @override
  Future<TradingAccount?> findByBrokerDetails({
    required String userId,
    required String brokerAccountNumber,
    String? brokerServer,
  }) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, user_id, broker_account_number, broker_server, account_name, '
        'environment, status, currency, created_at, updated_at '
        'FROM trading_accounts '
        'WHERE user_id = @user_id::uuid AND broker_account_number = @num '
        'AND COALESCE(broker_server, \'\') = COALESCE(@server, \'\') LIMIT 1',
      ),
      parameters: {
        'user_id': userId,
        'num': brokerAccountNumber,
        'server': brokerServer,
      },
    );
    if (result.isEmpty) return null;
    return _map(result.first);
  }

  @override
  Future<TradingAccount> create(TradingAccount account) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO trading_accounts '
        '(id, user_id, broker_account_number, broker_server, account_name, environment, status, currency, created_at, updated_at) '
        'VALUES (@id::uuid, @user_id::uuid, @num, @server, @name, @env, @status, @currency, @created, @updated)',
      ),
      parameters: {
        'id': account.id,
        'user_id': account.userId,
        'num': account.brokerAccountNumber,
        'server': account.brokerServer,
        'name': account.accountName,
        'env': account.environment.value,
        'status': account.status.value,
        'currency': account.currency,
        'created': account.createdAt.toUtc(),
        'updated': account.updatedAt.toUtc(),
      },
    );
    return account;
  }

  @override
  Future<TradingAccount> update(TradingAccount account) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'UPDATE trading_accounts SET account_name = @name, status = @status, '
        'currency = @currency, updated_at = @updated WHERE id = @id::uuid',
      ),
      parameters: {
        'id': account.id,
        'name': account.accountName,
        'status': account.status.value,
        'currency': account.currency,
        'updated': account.updatedAt.toUtc(),
      },
    );
    return account;
  }

  TradingAccount _map(ResultRow r) => TradingAccount(
        id: r[0].toString(),
        userId: r[1].toString(),
        brokerAccountNumber: r[2] as String,
        brokerServer: r[3] as String?,
        accountName: r[4] as String?,
        environment: AccountEnvironmentX.fromString(r[5] as String),
        status: AccountStatusX.fromString(r[6] as String),
        currency: r[7] as String?,
        createdAt: (r[8] as DateTime).toUtc(),
        updatedAt: (r[9] as DateTime).toUtc(),
      );
}

class PostgresLicenseRepository implements LicenseRepository {
  final PostgresPool pool;
  PostgresLicenseRepository(this.pool);

  @override
  Future<BotLicense?> findByAccountId(String tradingAccountId) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, trading_account_id, license_key, status, issued_at, expires_at, '
        'last_validated_at, created_at, updated_at '
        'FROM bot_licenses WHERE trading_account_id = @aid::uuid LIMIT 1',
      ),
      parameters: {'aid': tradingAccountId},
    );
    if (result.isEmpty) return null;
    return _map(result.first);
  }

  @override
  Future<BotLicense?> findByKey(String licenseKey) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, trading_account_id, license_key, status, issued_at, expires_at, '
        'last_validated_at, created_at, updated_at '
        'FROM bot_licenses WHERE license_key = @key LIMIT 1',
      ),
      parameters: {'key': licenseKey},
    );
    if (result.isEmpty) return null;
    return _map(result.first);
  }

  @override
  Future<BotLicense> create(BotLicense license) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO bot_licenses '
        '(id, trading_account_id, license_key, status, issued_at, expires_at, last_validated_at, created_at, updated_at) '
        'VALUES (@id::uuid, @aid::uuid, @key, @status, @issued, @expires, @validated, @created, @updated)',
      ),
      parameters: {
        'id': license.id,
        'aid': license.tradingAccountId,
        'key': license.licenseKey,
        'status': license.status.value,
        'issued': license.issuedAt.toUtc(),
        'expires': license.expiresAt?.toUtc(),
        'validated': license.lastValidatedAt?.toUtc(),
        'created': license.createdAt.toUtc(),
        'updated': license.updatedAt.toUtc(),
      },
    );
    return license;
  }

  @override
  Future<BotLicense> update(BotLicense license) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'UPDATE bot_licenses SET status = @status, expires_at = @expires, '
        'last_validated_at = @validated, updated_at = @updated WHERE id = @id::uuid',
      ),
      parameters: {
        'id': license.id,
        'status': license.status.value,
        'expires': license.expiresAt?.toUtc(),
        'validated': license.lastValidatedAt?.toUtc(),
        'updated': license.updatedAt.toUtc(),
      },
    );
    return license;
  }

  BotLicense _map(ResultRow r) => BotLicense(
        id: r[0].toString(),
        tradingAccountId: r[1].toString(),
        licenseKey: r[2] as String,
        status: LicenseStatusX.fromString(r[3] as String),
        issuedAt: (r[4] as DateTime).toUtc(),
        expiresAt: r[5] as DateTime?,
        lastValidatedAt: r[6] as DateTime?,
        createdAt: (r[7] as DateTime).toUtc(),
        updatedAt: (r[8] as DateTime).toUtc(),
      );
}

class PostgresSubscriptionRepository implements SubscriptionRepository {
  final PostgresPool pool;
  PostgresSubscriptionRepository(this.pool);

  @override
  Future<Subscription?> findActiveByAccountId(String tradingAccountId) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        "SELECT id, trading_account_id, plan_code, status, current_period_start, "
        "current_period_end, cancel_at_period_end, cancelled_at, created_at, updated_at "
        "FROM subscriptions WHERE trading_account_id = @aid::uuid "
        "AND status = 'active' AND current_period_end > NOW() "
        "ORDER BY current_period_end DESC LIMIT 1",
      ),
      parameters: {'aid': tradingAccountId},
    );
    if (result.isEmpty) return null;
    return _map(result.first);
  }

  @override
  Future<Subscription> create(Subscription sub) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO subscriptions '
        '(id, trading_account_id, plan_code, status, current_period_start, current_period_end, '
        'cancel_at_period_end, cancelled_at, created_at, updated_at) '
        'VALUES (@id::uuid, @aid::uuid, @plan, @status, @start, @end, @cancel, @cancelled, @created, @updated)',
      ),
      parameters: {
        'id': sub.id,
        'aid': sub.tradingAccountId,
        'plan': sub.planCode,
        'status': sub.status.value,
        'start': sub.currentPeriodStart.toUtc(),
        'end': sub.currentPeriodEnd.toUtc(),
        'cancel': sub.cancelAtPeriodEnd,
        'cancelled': sub.cancelledAt?.toUtc(),
        'created': sub.createdAt.toUtc(),
        'updated': sub.updatedAt.toUtc(),
      },
    );
    return sub;
  }

  @override
  Future<Subscription> update(Subscription sub) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'UPDATE subscriptions SET status = @status, current_period_end = @end, '
        'cancel_at_period_end = @cancel, cancelled_at = @cancelled, updated_at = @updated '
        'WHERE id = @id::uuid',
      ),
      parameters: {
        'id': sub.id,
        'status': sub.status.value,
        'end': sub.currentPeriodEnd.toUtc(),
        'cancel': sub.cancelAtPeriodEnd,
        'cancelled': sub.cancelledAt?.toUtc(),
        'updated': sub.updatedAt.toUtc(),
      },
    );
    return sub;
  }

  Subscription _map(ResultRow r) => Subscription(
        id: r[0].toString(),
        tradingAccountId: r[1].toString(),
        planCode: r[2] as String,
        status: SubscriptionStatusX.fromString(r[3] as String),
        currentPeriodStart: (r[4] as DateTime).toUtc(),
        currentPeriodEnd: (r[5] as DateTime).toUtc(),
        cancelAtPeriodEnd: r[6] as bool,
        cancelledAt: r[7] as DateTime?,
        createdAt: (r[8] as DateTime).toUtc(),
        updatedAt: (r[9] as DateTime).toUtc(),
      );
}