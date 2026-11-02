import 'package:test/test.dart';
import 'package:tenavix_server/src/auth/auth_service.dart';
import 'package:tenavix_server/src/auth/password_hasher.dart';
import 'package:tenavix_server/src/auth/token_service.dart';
import 'package:tenavix_server/src/audit/audit_service.dart';
import 'package:tenavix_server/src/common/types.dart';
import 'package:tenavix_server/src/database/in_memory_repositories.dart';

void main() {
  late AuthService auth;
  late InMemoryUserRepository users;
  late InMemoryRefreshTokenRepository tokens;
  late InMemoryAuditRepository auditRepo;

  setUp(() {
    users = InMemoryUserRepository();
    tokens = InMemoryRefreshTokenRepository();
    auditRepo = InMemoryAuditRepository();
    final audit = AuditService(auditRepo);
    final hasher = PasswordHasher();
    final tokenService = TokenService(jwtSecret: 'test-secret-key-at-least-32-chars!!');
    auth = AuthService(
      users: users,
      refreshTokens: tokens,
      passwordHasher: hasher,
      tokenService: tokenService,
      audit: audit,
    );
  });

  group('Registration', () {
    test('registers a new user with TRADER role', () async {
      final result = await auth.register(
        email: 'trader@example.com',
        password: 'securePass123!',
        fullName: 'Test Trader',
      );

      expect(result.user.email, 'trader@example.com');
      expect(result.user.roles, contains('TRADER'));
      expect(result.user.isAdmin, isFalse);
      expect(result.accessToken, isNotEmpty);
      expect(result.refreshToken, isNotEmpty);
      expect(auditRepo.events.any((e) => e.action == 'auth.register'), isTrue);
    });

    test('rejects duplicate email', () async {
      await auth.register(email: 'dup@example.com', password: 'securePass123!');
      expect(
        () => auth.register(email: 'dup@example.com', password: 'securePass123!'),
        throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('rejects short password', () async {
      expect(
        () => auth.register(email: 'a@b.com', password: 'short'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ErrorCodes.validation)),
      );
    });
  });

  group('Login', () {
    test('successful login returns tokens', () async {
      await auth.register(email: 'login@example.com', password: 'securePass123!');
      final result = await auth.login(
        email: 'login@example.com',
        password: 'securePass123!',
      );
      expect(result.accessToken, isNotEmpty);
      expect(result.user.email, 'login@example.com');
    });

    test('rejects wrong password', () async {
      await auth.register(email: 'wrong@example.com', password: 'securePass123!');
      expect(
        () => auth.login(email: 'wrong@example.com', password: 'wrongpassword'),
        throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 401)),
      );
    });
  });

  group('Refresh token rotation', () {
    test('refresh issues new tokens and invalidates old', () async {
      final first = await auth.register(
        email: 'refresh@example.com',
        password: 'securePass123!',
      );
      final second = await auth.refresh(refreshToken: first.refreshToken);

      expect(second.accessToken, isNotEmpty);
      expect(second.refreshToken, isNot(equals(first.refreshToken)));

      expect(
        () => auth.refresh(refreshToken: first.refreshToken),
        throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 401)),
      );
    });
  });

  group('Password hashing', () {
    test('hash is not reversible and verifies correctly', () {
      final hasher = PasswordHasher();
      final hash = hasher.hash('mySecretPassword!');
      expect(hash.startsWith('\$argon2id\$'), isTrue);
      expect(hasher.verify('mySecretPassword!', hash), isTrue);
      expect(hasher.verify('wrongPassword', hash), isFalse);
    });
  });
}