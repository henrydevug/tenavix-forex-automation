import 'package:test/test.dart';
import 'package:tenavix_server/src/auth/auth_service.dart';
import 'package:tenavix_server/src/auth/password_hasher.dart';
import 'package:tenavix_server/src/auth/token_service.dart';
import 'package:tenavix_server/src/auth/authorization.dart';
import 'package:tenavix_server/src/audit/audit_service.dart';
import 'package:tenavix_server/src/accounts/account_service.dart';
import 'package:tenavix_server/src/subscriptions/subscription_service.dart';
import 'package:tenavix_server/src/users/admin_service.dart';
import 'package:tenavix_server/src/common/types.dart';
import 'package:tenavix_server/src/database/in_memory_repositories.dart';
import 'package:tenavix_server/src/database/in_memory_account_repos.dart';

void main() {
  late AuthService auth;
  late AccountService accounts;
  late SubscriptionService subs;
  late AdminService admin;
  late TokenService tokenService;
  late InMemoryUserRepository userRepo;
  late InMemoryRefreshTokenRepository tokenRepo;
  late InMemoryLicenseRepository licenseRepo;

  setUp(() {
    userRepo = InMemoryUserRepository();
    tokenRepo = InMemoryRefreshTokenRepository();
    final auditRepo = InMemoryAuditRepository();
    final audit = AuditService(auditRepo);
    tokenService = TokenService(
      jwtSecret: 'test-secret-key-at-least-32-chars!!',
      accessTokenTtl: const Duration(seconds: 2), // short for expiry test
    );
    auth = AuthService(
      users: userRepo,
      refreshTokens: tokenRepo,
      passwordHasher: PasswordHasher(),
      tokenService: tokenService,
      audit: audit,
    );
    final accountRepo = InMemoryTradingAccountRepository();
    licenseRepo = InMemoryLicenseRepository();
    final subRepo = InMemorySubscriptionRepository();
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
    admin = AdminService(
      users: userRepo,
      refreshTokens: tokenRepo,
      audit: audit,
    );
  });

  group('Security: Token expiry & rotation', () {
    test('expired access token is rejected by verifyAccessToken', () async {
      final reg = await auth.register(
        email: 'exp@example.com',
        password: 'securePass123!',
      );
      // Wait for short TTL
      await Future.delayed(const Duration(seconds: 3));
      expect(
        () => tokenService.verifyAccessToken(reg.accessToken),
        throwsA(anything),
      );
    });

    test('revoked refresh token cannot be reused', () async {
      final reg = await auth.register(
        email: 'rev@example.com',
        password: 'securePass123!',
      );
      final refreshed = await auth.refresh(refreshToken: reg.refreshToken);
      // Old token must fail
      expect(
        () => auth.refresh(refreshToken: reg.refreshToken),
        throwsA(isA<AppException>().having((e) => e.statusCode, 's', 401)),
      );
      // New one works
      final again = await auth.refresh(refreshToken: refreshed.refreshToken);
      expect(again.accessToken, isNotEmpty);
    });
  });

  group('Security: Suspended user loses access', () {
    test('suspended user cannot login', () async {
      final reg = await auth.register(
        email: 'sus@example.com',
        password: 'securePass123!',
      );
      // Promote a separate admin
      final adminReg = await auth.register(
        email: 'adm@example.com',
        password: 'securePass123!',
      );
      await userRepo.assignRole(adminReg.user.id, 'ADMIN');
      final adminUser = (await userRepo.findById(adminReg.user.id))!
          .copyWith(roles: await userRepo.getRoleNames(adminReg.user.id));

      await admin.suspendUser(caller: adminUser, targetUserId: reg.user.id);

      expect(
        () => auth.login(email: 'sus@example.com', password: 'securePass123!'),
        throwsA(isA<AppException>().having((e) => e.statusCode, 's', 403)),
      );
    });
  });

  group('Security: RBAC & isolation', () {
    test('TRADER cannot call requireAdmin', () async {
      final reg = await auth.register(
        email: 'trader2@example.com',
        password: 'securePass123!',
      );
      expect(
        () => Authorization.requireAdmin(reg.user),
        throwsA(isA<AppException>().having((e) => e.statusCode, 's', 403)),
      );
    });

    test('cross-account access is rejected', () async {
      final u1 = await auth.register(email: 'c1@example.com', password: 'securePass123!');
      final u2 = await auth.register(email: 'c2@example.com', password: 'securePass123!');
      final acc = await accounts.registerAccount(
        caller: u1.user,
        brokerAccountNumber: '777',
      );
      expect(
        () => accounts.getAccount(caller: u2.user, accountId: acc.id),
        throwsA(isA<AppException>().having((e) => e.statusCode, 's', 403)),
      );
    });

    test('TRADER cannot suspend users', () async {
      final trader = await auth.register(email: 't3@example.com', password: 'securePass123!');
      final other = await auth.register(email: 'o3@example.com', password: 'securePass123!');
      expect(
        () => admin.suspendUser(caller: trader.user, targetUserId: other.user.id),
        throwsA(isA<AppException>().having((e) => e.statusCode, 's', 403)),
      );
    });
  });

  group('Security: License validation is independent of user JWT', () {
    test('license validation works with key + account number only', () async {
      final reg = await auth.register(email: 'lic2@example.com', password: 'securePass123!');
      final acc = await accounts.registerAccount(
        caller: reg.user,
        brokerAccountNumber: '88888',
      );
      final license = await licenseRepo.findByAccountId(acc.id);
      expect(license, isNotNull);

      // No user context required
      final result = await accounts.validateLicense(
        licenseKey: license!.licenseKey,
        brokerAccountNumber: '88888',
      );
      expect(result.containsKey('valid'), isTrue);
      expect(result['licenseStatus'], 'active');
    });

    test('wrong account number fails validation', () async {
      final reg = await auth.register(email: 'lic3@example.com', password: 'securePass123!');
      final acc = await accounts.registerAccount(
        caller: reg.user,
        brokerAccountNumber: '99999',
      );
      final license = await licenseRepo.findByAccountId(acc.id);

      final result = await accounts.validateLicense(
        licenseKey: license!.licenseKey,
        brokerAccountNumber: 'WRONG',
      );
      expect(result['valid'], isFalse);
    });
  });

  group('Subscription activation enables license validity', () {
    test('after activation, validateLicense reports subscriptionActive true', () async {
      final reg = await auth.register(email: 'sub1@example.com', password: 'securePass123!');
      final acc = await accounts.registerAccount(
        caller: reg.user,
        brokerAccountNumber: '10001',
      );
      final license = await licenseRepo.findByAccountId(acc.id);

      var result = await accounts.validateLicense(
        licenseKey: license!.licenseKey,
        brokerAccountNumber: '10001',
      );
      expect(result['subscriptionActive'], isFalse);

      await subs.activateStandard(caller: reg.user, tradingAccountId: acc.id);

      result = await accounts.validateLicense(
        licenseKey: license.licenseKey,
        brokerAccountNumber: '10001',
      );
      expect(result['valid'], isTrue);
      expect(result['subscriptionActive'], isTrue);
    });
  });
}
