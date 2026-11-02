import 'package:test/test.dart';
import 'package:tenavix_server/src/accounts/account_service.dart';
import 'package:tenavix_server/src/auth/auth_service.dart';
import 'package:tenavix_server/src/auth/authorization.dart';
import 'package:tenavix_server/src/auth/password_hasher.dart';
import 'package:tenavix_server/src/auth/token_service.dart';
import 'package:tenavix_server/src/audit/audit_service.dart';
import 'package:tenavix_server/src/common/types.dart';
import 'package:tenavix_server/src/database/in_memory_repositories.dart';
import 'package:tenavix_server/src/database/in_memory_account_repos.dart';
import 'package:tenavix_server/src/users/user.dart';

void main() {
  late AuthService auth;
  late AccountService accounts;
  late InMemoryUserRepository userRepo;
  late InMemoryTradingAccountRepository accountRepo;
  late InMemoryLicenseRepository licenseRepo;
  late InMemorySubscriptionRepository subRepo;

  setUp(() {
    userRepo = InMemoryUserRepository();
    final tokenRepo = InMemoryRefreshTokenRepository();
    final auditRepo = InMemoryAuditRepository();
    final audit = AuditService(auditRepo);
    auth = AuthService(
      users: userRepo,
      refreshTokens: tokenRepo,
      passwordHasher: PasswordHasher(),
      tokenService: TokenService(jwtSecret: 'test-secret-key-at-least-32-chars!!'),
      audit: audit,
    );
    accountRepo = InMemoryTradingAccountRepository();
    licenseRepo = InMemoryLicenseRepository();
    subRepo = InMemorySubscriptionRepository();
    accounts = AccountService(
      accounts: accountRepo,
      licenses: licenseRepo,
      subscriptions: subRepo,
      audit: audit,
    );
  });

  group('Account registration & isolation', () {
    test('trader can register a demo trading account and receives license', () async {
      final reg = await auth.register(
        email: 't1@example.com',
        password: 'securePass123!',
      );
      final account = await accounts.registerAccount(
        caller: reg.user,
        brokerAccountNumber: '12345678',
        environment: AccountEnvironment.demo,
      );

      expect(account.userId, reg.user.id);
      expect(account.environment, AccountEnvironment.demo);
      expect(account.isDemo, isTrue);

      final license = await licenseRepo.findByAccountId(account.id);
      expect(license, isNotNull);
      expect(license!.licenseKey.startsWith('TNX-'), isTrue);
      expect(license.isUsable, isTrue);
    });

    test('account isolation: user cannot access another users account', () async {
      final u1 = await auth.register(email: 'u1@example.com', password: 'securePass123!');
      final u2 = await auth.register(email: 'u2@example.com', password: 'securePass123!');

      final acc1 = await accounts.registerAccount(
        caller: u1.user,
        brokerAccountNumber: '111',
      );

      expect(
        () => accounts.getAccount(caller: u2.user, accountId: acc1.id),
        throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('admin can access any account', () async {
      final trader = await auth.register(email: 'tr@example.com', password: 'securePass123!');
      // Promote to admin for test
      await userRepo.assignRole(trader.user.id, 'ADMIN');
      final adminUser = (await userRepo.findById(trader.user.id))!
          .copyWith(roles: await userRepo.getRoleNames(trader.user.id));

      final other = await auth.register(email: 'other@example.com', password: 'securePass123!');
      final acc = await accounts.registerAccount(
        caller: other.user,
        brokerAccountNumber: '999',
      );

      final fetched = await accounts.getAccount(caller: adminUser, accountId: acc.id);
      expect(fetched.id, acc.id);
    });
  });

  group('License validation', () {
    test('valid license with inactive subscription returns valid=false for trading', () async {
      final reg = await auth.register(email: 'lic@example.com', password: 'securePass123!');
      final account = await accounts.registerAccount(
        caller: reg.user,
        brokerAccountNumber: '55555',
      );
      final license = await licenseRepo.findByAccountId(account.id);

      final result = await accounts.validateLicense(
        licenseKey: license!.licenseKey,
        brokerAccountNumber: '55555',
      );

      expect(result['valid'], isFalse); // no active subscription yet
      expect(result['licenseStatus'], 'active');
      expect(result['subscriptionActive'], isFalse);
    });
  });

  group('Authorization helpers', () {
    test('requireAdmin rejects trader', () {
      final trader = User(
        id: '1',
        email: 't@t.com',
        passwordHash: 'x',
        status: UserStatus.active,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        roles: const ['TRADER'],
      );
      expect(
        () => Authorization.requireAdmin(trader),
        throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });
}