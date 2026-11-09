import 'package:test/test.dart';
import 'package:tenavix_server/src/auth/auth_service.dart';
import 'package:tenavix_server/src/auth/password_hasher.dart';
import 'package:tenavix_server/src/auth/token_service.dart';
import 'package:tenavix_server/src/audit/audit_service.dart';
import 'package:tenavix_server/src/common/types.dart';
import 'package:tenavix_server/src/database/in_memory_repositories.dart';
import 'package:tenavix_server/src/users/admin_service.dart';
import 'package:tenavix_server/src/users/user.dart';

void main() {
  late AuthService auth;
  late AdminService admin;
  late InMemoryUserRepository users;
  late InMemoryRefreshTokenRepository tokens;
  late InMemoryAuditRepository auditRepo;

  setUp(() {
    users = InMemoryUserRepository();
    tokens = InMemoryRefreshTokenRepository();
    auditRepo = InMemoryAuditRepository();
    final audit = AuditService(auditRepo);
    auth = AuthService(
      users: users,
      refreshTokens: tokens,
      passwordHasher: PasswordHasher(),
      tokenService: TokenService(jwtSecret: 'test-secret-key-at-least-32-chars!!'),
      audit: audit,
    );
    admin = AdminService(
      users: users,
      refreshTokens: tokens,
      audit: audit,
    );
  });

  Future<User> registerTrader(String email) async {
    final r = await auth.register(email: email, password: 'securePass123!');
    return r.user;
  }

  Future<User> promoteAdmin(User u) async {
    await users.assignRole(u.id, 'ADMIN');
    final roles = await users.getRoleNames(u.id);
    return u.copyWith(roles: roles);
  }

  test('TRADER cannot list users or audit', () async {
    final trader = await registerTrader('t-dir@example.com');
    expect(() => admin.listUsers(caller: trader), throwsA(isA<AppException>()));
    expect(() => admin.listAuditEvents(caller: trader), throwsA(isA<AppException>()));
  });

  test('ADMIN can list users and audit events', () async {
    final a = await promoteAdmin(await registerTrader('a-dir@example.com'));
    await registerTrader('other@example.com');
    final page = await admin.listUsers(caller: a, limit: 10);
    expect(page.total >= 2, isTrue);
    expect(page.users.any((u) => u.email == 'other@example.com'), isTrue);
    // password hash must not appear in public json
    for (final u in page.users) {
      expect(u.toPublicJson().containsKey('passwordHash'), isFalse);
    }
    await admin.suspendUser(caller: a, targetUserId: page.users.first.id, reason: 'test');
    final events = await admin.listAuditEvents(caller: a, limit: 20);
    expect(events.any((e) => e.action == 'admin.user.suspend'), isTrue);
  });
}
