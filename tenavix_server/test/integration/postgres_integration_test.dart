import 'package:test/test.dart';
import 'package:tenavix_server/src/auth/auth_service.dart';
import 'package:tenavix_server/src/auth/password_hasher.dart';
import 'package:tenavix_server/src/auth/token_service.dart';
import 'package:tenavix_server/src/audit/audit_service.dart';
import 'package:tenavix_server/src/accounts/account_service.dart';
import 'package:tenavix_server/src/subscriptions/subscription_service.dart';
import 'package:tenavix_server/src/database/postgres_connection.dart';
import 'package:tenavix_server/src/database/postgres_user_repository.dart';
import 'package:tenavix_server/src/database/postgres_account_repository.dart';
import 'package:tenavix_server/src/database/postgres_audit_repository.dart';
import 'package:tenavix_server/src/common/types.dart';

/// Integration tests against a real PostgreSQL instance.
/// Requires the tenavix database and migration 001 to be applied.
void main() {
  late PostgresPool pool;
  late AuthService auth;
  late AccountService accounts;
  late SubscriptionService subs;

  setUpAll(() async {
    // Credentials must come from environment (see .env.example).
    // Example: TENAVIX_DB_PASSWORD=... dart test test/integration
    pool = PostgresPool.fromEnvironment();
    final conn = await pool.connection;
    await conn.execute('SELECT 1');
  });

  tearDownAll(() async {
    await pool.close();
  });

  setUp(() {
    final userRepo = PostgresUserRepository(pool);
    final tokenRepo = PostgresRefreshTokenRepository(pool);
    final auditRepo = PostgresAuditRepository(pool);
    final audit = AuditService(auditRepo);
    auth = AuthService(
      users: userRepo,
      refreshTokens: tokenRepo,
      passwordHasher: PasswordHasher(),
      tokenService: TokenService(jwtSecret: 'integration-test-secret-key-32ch'),
      audit: audit,
    );
    final accountRepo = PostgresTradingAccountRepository(pool);
    final licenseRepo = PostgresLicenseRepository(pool);
    final subRepo = PostgresSubscriptionRepository(pool);
    accounts = AccountService(
      accounts: accountRepo,
      licenses: licenseRepo,
      subscriptions: subRepo,
      audit: audit,
    );
    subs = SubscriptionService(
      subscriptions: subRepo,
      accounts: accountRepo,
      audit: audit,
    );
  });

  test('register + login persists to PostgreSQL', () async {
    final email = 'pg_${DateTime.now().millisecondsSinceEpoch}@example.com';
    final reg = await auth.register(
      email: email,
      password: 'securePass123!',
      fullName: 'PG User',
    );
    expect(reg.user.id, isNotEmpty);
    expect(reg.user.roles, contains('TRADER'));

    final login = await auth.login(email: email, password: 'securePass123!');
    expect(login.user.email, email);
    expect(login.accessToken, isNotEmpty);
  });

  test('account + license + subscription full flow on PostgreSQL', () async {
    final email = 'pg_acc_${DateTime.now().millisecondsSinceEpoch}@example.com';
    final reg = await auth.register(email: email, password: 'securePass123!');

    final account = await accounts.registerAccount(
      caller: reg.user,
      brokerAccountNumber: '${DateTime.now().millisecondsSinceEpoch}',
      environment: AccountEnvironment.demo,
    );
    expect(account.isDemo, isTrue);

    final list = await accounts.listMyAccounts(reg.user);
    expect(list.any((a) => a.id == account.id), isTrue);

    // License exists
    final licenseRepo = PostgresLicenseRepository(pool);
    final license = await licenseRepo.findByAccountId(account.id);
    expect(license, isNotNull);
    expect(license!.licenseKey.startsWith('TNX-'), isTrue);

    // Before subscription
    var validation = await accounts.validateLicense(
      licenseKey: license.licenseKey,
      brokerAccountNumber: account.brokerAccountNumber,
    );
    expect(validation['subscriptionActive'], isFalse);

    // Activate subscription
    final sub = await subs.activateStandard(
      caller: reg.user,
      tradingAccountId: account.id,
    );
    expect(sub.isActive, isTrue);

    validation = await accounts.validateLicense(
      licenseKey: license.licenseKey,
      brokerAccountNumber: account.brokerAccountNumber,
    );
    expect(validation['valid'], isTrue);
    expect(validation['subscriptionActive'], isTrue);
  });

  test('refresh token rotation persists revocation', () async {
    final email = 'pg_ref_${DateTime.now().millisecondsSinceEpoch}@example.com';
    final reg = await auth.register(email: email, password: 'securePass123!');
    final second = await auth.refresh(refreshToken: reg.refreshToken);
    expect(second.refreshToken, isNot(equals(reg.refreshToken)));

    expect(
      () => auth.refresh(refreshToken: reg.refreshToken),
      throwsA(isA<AppException>()),
    );
  });
}