import '../auth/authorization.dart';
import '../audit/audit_service.dart';
import '../common/types.dart';
import '../users/user.dart';
import '../database/postgres_user_repository.dart';
import '../auth/auth_service.dart';

/// Administrative operations (ADMIN role only).
class AdminService {
  final UserRepository users;
  final PostgresUserRepository? postgresUsers; // for suspend
  final RefreshTokenRepository refreshTokens;
  final AuditService audit;

  AdminService({
    required this.users,
    this.postgresUsers,
    required this.refreshTokens,
    required this.audit,
  });

  /// Suspend a user: set status and revoke all sessions.
  Future<void> suspendUser({
    required User caller,
    required String targetUserId,
    String? reason,
  }) async {
    Authorization.requireAdmin(caller);

    final target = await users.findById(targetUserId);
    if (target == null) {
      throw const AppException(
        code: ErrorCodes.notFound,
        message: 'User not found',
        statusCode: 404,
      );
    }

    if (postgresUsers != null) {
      await postgresUsers!.suspendUser(targetUserId);
    } else {
      await users.update(target.copyWith(
        status: UserStatus.suspended,
        updatedAt: DateTime.now().toUtc(),
      ));
    }

    // Force logout all sessions
    await refreshTokens.revokeAllForUser(targetUserId);

    await audit.record(
      actorUserId: caller.id,
      action: 'admin.user.suspend',
      resourceType: 'user',
      resourceId: targetUserId,
      outcome: AuditOutcome.success,
      details: {'reason': reason},
    );
  }

  /// Paginated user directory for administrators only.
  Future<({List<User> users, int total})> listUsers({
    required User caller,
    String? emailContains,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    Authorization.requireAdmin(caller);
    return users.listUsers(
      emailContains: emailContains,
      status: status,
      limit: limit,
      offset: offset,
    );
  }

  /// Recent audit events for administrators only (no secrets in details by convention).
  Future<List<AuditEvent>> listAuditEvents({
    required User caller,
    int limit = 50,
    String? actorUserId,
  }) async {
    Authorization.requireAdmin(caller);
    final lim = limit.clamp(1, 200);
    return audit.listRecent(limit: lim, actorUserId: actorUserId);
  }
}