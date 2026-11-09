import 'package:uuid/uuid.dart';
import '../common/types.dart';
import '../users/user.dart';
import '../audit/audit_service.dart';
import 'password_hasher.dart';
import 'token_service.dart';

/// Result of a successful authentication.
class AuthResult {
  final User user;
  final String accessToken;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });
}

/// Abstraction for user persistence (implemented by Postgres or in-memory for tests).
abstract class UserRepository {
  Future<User?> findByEmail(String email);
  Future<User?> findById(String id);
  Future<User> create(User user);
  Future<User> update(User user);
  Future<List<String>> getRoleNames(String userId);
  Future<void> assignRole(String userId, String roleName);

  /// Admin directory listing. Callers must not expose passwordHash.
  Future<({List<User> users, int total})> listUsers({
    String? emailContains,
    String? status,
    int limit = 50,
    int offset = 0,
  });
}

/// Abstraction for refresh token persistence.
abstract class RefreshTokenRepository {
  Future<void> save(RefreshTokenRecord record);
  Future<RefreshTokenRecord?> findByHash(String tokenHash);
  Future<void> revoke(String id, {String? replacedByTokenId});
  Future<void> revokeAllForUser(String userId);
}

/// Core authentication use-cases.
class AuthService {
  final UserRepository users;
  final RefreshTokenRepository refreshTokens;
  final PasswordHasher passwordHasher;
  final TokenService tokenService;
  final AuditService audit;
  final _uuid = const Uuid();

  AuthService({
    required this.users,
    required this.refreshTokens,
    required this.passwordHasher,
    required this.tokenService,
    required this.audit,
  });

  /// Register a new trader (default role: TRADER).
  Future<AuthResult> register({
    required String email,
    required String password,
    String? fullName,
    String? ipAddress,
    String? userAgent,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    _validateEmail(normalizedEmail);
    _validatePassword(password);

    final existing = await users.findByEmail(normalizedEmail);
    if (existing != null) {
      throw const AppException(
        code: ErrorCodes.conflict,
        message: 'Email already registered',
        statusCode: 409,
      );
    }

    final now = DateTime.now().toUtc();
    final user = User(
      id: _uuid.v4(),
      email: normalizedEmail,
      passwordHash: passwordHasher.hash(password),
      fullName: fullName?.trim(),
      status: UserStatus.active,
      createdAt: now,
      updatedAt: now,
      roles: const [],
    );

    final created = await users.create(user);
    await users.assignRole(created.id, 'TRADER');
    final roles = await users.getRoleNames(created.id);
    final withRoles = created.copyWith(roles: roles);

    await audit.record(
      actorUserId: withRoles.id,
      action: 'auth.register',
      resourceType: 'user',
      resourceId: withRoles.id,
      outcome: AuditOutcome.success,
      ipAddress: ipAddress,
      userAgent: userAgent,
    );

    return _issueTokens(withRoles, ipAddress: ipAddress, userAgent: userAgent);
  }

  /// Authenticate with email + password.
  Future<AuthResult> login({
    required String email,
    required String password,
    String? ipAddress,
    String? userAgent,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final user = await users.findByEmail(normalizedEmail);

    if (user == null || !passwordHasher.verify(password, user.passwordHash)) {
      await audit.record(
        actorUserId: user?.id,
        action: 'auth.login',
        resourceType: 'user',
        resourceId: user?.id,
        outcome: AuditOutcome.failure,
        details: {'reason': 'invalid_credentials'},
        ipAddress: ipAddress,
        userAgent: userAgent,
      );
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'Invalid email or password',
        statusCode: 401,
      );
    }

    if (user.status == UserStatus.suspended) {
      throw const AppException(
        code: ErrorCodes.forbidden,
        message: 'Account is suspended',
        statusCode: 403,
      );
    }
    if (user.status == UserStatus.deleted) {
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'Invalid email or password',
        statusCode: 401,
      );
    }

    final roles = await users.getRoleNames(user.id);
    final withRoles = user.copyWith(roles: roles, lastLoginAt: DateTime.now().toUtc());
    await users.update(withRoles);

    await audit.record(
      actorUserId: withRoles.id,
      action: 'auth.login',
      resourceType: 'user',
      resourceId: withRoles.id,
      outcome: AuditOutcome.success,
      ipAddress: ipAddress,
      userAgent: userAgent,
    );

    return _issueTokens(withRoles, ipAddress: ipAddress, userAgent: userAgent);
  }

  /// Rotate refresh token and issue new access + refresh pair.
  Future<AuthResult> refresh({
    required String refreshToken,
    String? ipAddress,
    String? userAgent,
  }) async {
    final hash = tokenService.hashRefreshToken(refreshToken);
    final record = await refreshTokens.findByHash(hash);

    if (record == null || !record.isValid) {
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'Invalid or expired refresh token',
        statusCode: 401,
      );
    }

    // Rotate: revoke old, issue new
    final user = await users.findById(record.userId);
    if (user == null || !user.isActive) {
      await refreshTokens.revoke(record.id);
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'User not found or inactive',
        statusCode: 401,
      );
    }

    final roles = await users.getRoleNames(user.id);
    final withRoles = user.copyWith(roles: roles);

    final newRefreshValue = tokenService.createRefreshTokenValue();
    final newRefreshId = tokenService.newRefreshTokenId();
    final newHash = tokenService.hashRefreshToken(newRefreshValue);
    final expiresAt = DateTime.now().toUtc().add(tokenService.refreshTokenTtl);

    // Insert new token first so FK on replaced_by_token_id is satisfied.
    await refreshTokens.save(RefreshTokenRecord(
      id: newRefreshId,
      userId: withRoles.id,
      tokenHash: newHash,
      expiresAt: expiresAt,
      createdAt: DateTime.now().toUtc(),
      userAgent: userAgent,
      ipAddress: ipAddress,
    ));
    await refreshTokens.revoke(record.id, replacedByTokenId: newRefreshId);

    final accessToken = tokenService.createAccessToken(
      userId: withRoles.id,
      email: withRoles.email,
      roles: withRoles.roles,
    );

    return AuthResult(
      user: withRoles,
      accessToken: accessToken,
      refreshToken: newRefreshValue,
      refreshExpiresAt: expiresAt,
    );
  }

  /// Logout: revoke the presented refresh token (or all for user).
  Future<void> logout({
    required String userId,
    String? refreshToken,
    bool allSessions = false,
  }) async {
    if (allSessions) {
      await refreshTokens.revokeAllForUser(userId);
    } else if (refreshToken != null) {
      final hash = tokenService.hashRefreshToken(refreshToken);
      final record = await refreshTokens.findByHash(hash);
      if (record != null && record.userId == userId) {
        await refreshTokens.revoke(record.id);
      }
    }
    await audit.record(
      actorUserId: userId,
      action: 'auth.logout',
      resourceType: 'user',
      resourceId: userId,
      outcome: AuditOutcome.success,
    );
  }

  Future<AuthResult> _issueTokens(
    User user, {
    String? ipAddress,
    String? userAgent,
  }) async {
    final accessToken = tokenService.createAccessToken(
      userId: user.id,
      email: user.email,
      roles: user.roles,
    );
    final refreshValue = tokenService.createRefreshTokenValue();
    final refreshId = tokenService.newRefreshTokenId();
    final hash = tokenService.hashRefreshToken(refreshValue);
    final expiresAt = DateTime.now().toUtc().add(tokenService.refreshTokenTtl);

    await refreshTokens.save(RefreshTokenRecord(
      id: refreshId,
      userId: user.id,
      tokenHash: hash,
      expiresAt: expiresAt,
      createdAt: DateTime.now().toUtc(),
      userAgent: userAgent,
      ipAddress: ipAddress,
    ));

    return AuthResult(
      user: user,
      accessToken: accessToken,
      refreshToken: refreshValue,
      refreshExpiresAt: expiresAt,
    );
  }

  void _validateEmail(String email) {
    final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!re.hasMatch(email) || email.length > 255) {
      throw const AppException(
        code: ErrorCodes.validation,
        message: 'Invalid email address',
        statusCode: 400,
      );
    }
  }

  void _validatePassword(String password) {
    if (password.length < 10) {
      throw const AppException(
        code: ErrorCodes.validation,
        message: 'Password must be at least 10 characters',
        statusCode: 400,
      );
    }
    if (password.length > 128) {
      throw const AppException(
        code: ErrorCodes.validation,
        message: 'Password too long',
        statusCode: 400,
      );
    }
  }
}