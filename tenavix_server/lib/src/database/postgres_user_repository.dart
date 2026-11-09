import 'package:postgres/postgres.dart';
import '../auth/auth_service.dart';
import '../auth/token_service.dart';
import '../users/user.dart';
import '../common/types.dart';
import 'postgres_connection.dart';

class PostgresUserRepository implements UserRepository {
  final PostgresPool pool;

  PostgresUserRepository(this.pool);

  @override
  Future<User?> findByEmail(String email) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, email::text, password_hash, full_name, status, email_verified_at, '
        'created_at, updated_at, last_login_at FROM users WHERE email = @email LIMIT 1',
      ),
      parameters: {'email': email.toLowerCase()},
    );
    if (result.isEmpty) return null;
    return _mapUser(result.first);
  }

  @override
  Future<User?> findById(String id) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, email::text, password_hash, full_name, status, email_verified_at, '
        'created_at, updated_at, last_login_at FROM users WHERE id = @id::uuid LIMIT 1',
      ),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    return _mapUser(result.first);
  }

  @override
  Future<User> create(User user) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO users (id, email, password_hash, full_name, status, created_at, updated_at) '
        'VALUES (@id::uuid, @email, @password_hash, @full_name, @status, @created_at, @updated_at)',
      ),
      parameters: {
        'id': user.id,
        'email': user.email.toLowerCase(),
        'password_hash': user.passwordHash,
        'full_name': user.fullName,
        'status': user.status.value,
        'created_at': user.createdAt.toUtc(),
        'updated_at': user.updatedAt.toUtc(),
      },
    );
    return user;
  }

  @override
  Future<User> update(User user) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'UPDATE users SET full_name = @full_name, status = @status, '
        'email_verified_at = @email_verified_at, last_login_at = @last_login_at, '
        'updated_at = @updated_at WHERE id = @id::uuid',
      ),
      parameters: {
        'id': user.id,
        'full_name': user.fullName,
        'status': user.status.value,
        'email_verified_at': user.emailVerifiedAt?.toUtc(),
        'last_login_at': user.lastLoginAt?.toUtc(),
        'updated_at': user.updatedAt.toUtc(),
      },
    );
    return user;
  }

  @override
  Future<List<String>> getRoleNames(String userId) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT r.name FROM user_roles ur '
        'JOIN roles r ON r.id = ur.role_id '
        'WHERE ur.user_id = @user_id::uuid ORDER BY r.name',
      ),
      parameters: {'user_id': userId},
    );
    return result.map((r) => r[0] as String).toList();
  }

  @override
  Future<({List<User> users, int total})> listUsers({
    String? emailContains,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final conn = await pool.connection;
    final lim = limit.clamp(1, 200);
    final off = offset < 0 ? 0 : offset;
    final where = <String>[];
    final params = <String, Object?>{'lim': lim, 'off': off};
    if (emailContains != null && emailContains.trim().isNotEmpty) {
      where.add("email::text ILIKE '%' || @q || '%'");
      params['q'] = emailContains.trim();
    }
    if (status != null && status.trim().isNotEmpty) {
      where.add('status = @status');
      params['status'] = status.trim().toLowerCase();
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final countResult = await conn.execute(
      Sql.named('SELECT COUNT(*)::int FROM users $whereSql'),
      parameters: params,
    );
    final total = countResult.first[0] as int;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, email::text, password_hash, full_name, status, email_verified_at, '
        'created_at, updated_at, last_login_at FROM users $whereSql '
        'ORDER BY created_at DESC LIMIT @lim OFFSET @off',
      ),
      parameters: params,
    );
    final users = <User>[];
    for (final row in result) {
      var u = _mapUser(row);
      final roles = await getRoleNames(u.id);
      u = u.copyWith(roles: roles);
      users.add(u);
    }
    return (users: users, total: total);
  }

  @override
  Future<void> assignRole(String userId, String roleName) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO user_roles (user_id, role_id) '
        'SELECT @user_id::uuid, id FROM roles WHERE name = @role_name '
        'ON CONFLICT DO NOTHING',
      ),
      parameters: {'user_id': userId, 'role_name': roleName},
    );
  }

  /// Admin: suspend a user.
  Future<void> suspendUser(String userId) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        "UPDATE users SET status = 'suspended', updated_at = NOW() WHERE id = @id::uuid",
      ),
      parameters: {'id': userId},
    );
  }

  User _mapUser(ResultRow row) {
    return User(
      id: row[0].toString(),
      email: _asString(row[1])!,
      passwordHash: _asString(row[2])!,
      fullName: _asString(row[3]),
      status: UserStatusX.fromString(_asString(row[4]) ?? 'active'),
      emailVerifiedAt: row[5] is DateTime ? (row[5] as DateTime).toUtc() : null,
      createdAt: (row[6] as DateTime).toUtc(),
      updatedAt: (row[7] as DateTime).toUtc(),
      lastLoginAt: row[8] is DateTime ? (row[8] as DateTime).toUtc() : null,
    );
  }

  static String? _asString(Object? v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }
}

class PostgresRefreshTokenRepository implements RefreshTokenRepository {
  final PostgresPool pool;

  PostgresRefreshTokenRepository(this.pool);

  @override
  Future<void> save(RefreshTokenRecord record) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at, created_at, user_agent, ip_address) '
        'VALUES (@id::uuid, @user_id::uuid, @token_hash, @expires_at, @created_at, @user_agent, @ip_address::inet)',
      ),
      parameters: {
        'id': record.id,
        'user_id': record.userId,
        'token_hash': record.tokenHash,
        'expires_at': record.expiresAt.toUtc(),
        'created_at': record.createdAt.toUtc(),
        'user_agent': record.userAgent,
        'ip_address': record.ipAddress,
      },
    );
  }

  @override
  Future<RefreshTokenRecord?> findByHash(String tokenHash) async {
    final conn = await pool.connection;
    final result = await conn.execute(
      Sql.named(
        'SELECT id, user_id, token_hash, expires_at, created_at, revoked_at, '
        'replaced_by_token_id, user_agent, ip_address::text '
        'FROM refresh_tokens WHERE token_hash = @hash LIMIT 1',
      ),
      parameters: {'hash': tokenHash},
    );
    if (result.isEmpty) return null;
    final r = result.first;
    return RefreshTokenRecord(
      id: r[0].toString(),
      userId: r[1].toString(),
      tokenHash: r[2] as String,
      expiresAt: (r[3] as DateTime).toUtc(),
      createdAt: (r[4] as DateTime).toUtc(),
      revokedAt: r[5] as DateTime?,
      replacedByTokenId: r[6]?.toString(),
      userAgent: r[7] as String?,
      ipAddress: r[8] as String?,
    );
  }

  @override
  Future<void> revoke(String id, {String? replacedByTokenId}) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'UPDATE refresh_tokens SET revoked_at = NOW(), replaced_by_token_id = @replaced::uuid '
        'WHERE id = @id::uuid',
      ),
      parameters: {'id': id, 'replaced': replacedByTokenId},
    );
  }

  @override
  Future<void> revokeAllForUser(String userId) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'UPDATE refresh_tokens SET revoked_at = NOW() '
        'WHERE user_id = @user_id::uuid AND revoked_at IS NULL',
      ),
      parameters: {'user_id': userId},
    );
  }
}