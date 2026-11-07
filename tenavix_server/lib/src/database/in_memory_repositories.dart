import '../auth/auth_service.dart';
import '../auth/token_service.dart';
import '../audit/audit_service.dart';
import '../users/user.dart';

/// In-memory implementations for unit & integration tests.
/// Production will use PostgreSQL implementations of the same interfaces.

class InMemoryUserRepository implements UserRepository {
  final Map<String, User> _byId = {};
  final Map<String, String> _emailToId = {};
  final Map<String, Set<String>> _userRoles = {}; // userId -> role names

  @override
  Future<User?> findByEmail(String email) async {
    final id = _emailToId[email.toLowerCase()];
    if (id == null) return null;
    return _byId[id];
  }

  @override
  Future<User?> findById(String id) async => _byId[id];

  @override
  Future<User> create(User user) async {
    if (_emailToId.containsKey(user.email.toLowerCase())) {
      throw StateError('Email already exists');
    }
    _byId[user.id] = user;
    _emailToId[user.email.toLowerCase()] = user.id;
    _userRoles[user.id] = {};
    return user;
  }

  @override
  Future<User> update(User user) async {
    _byId[user.id] = user;
    return user;
  }

  @override
  Future<List<String>> getRoleNames(String userId) async {
    return (_userRoles[userId] ?? {}).toList()..sort();
  }

  @override
  Future<void> assignRole(String userId, String roleName) async {
    _userRoles.putIfAbsent(userId, () => {}).add(roleName);
  }
}

class InMemoryRefreshTokenRepository implements RefreshTokenRepository {
  final Map<String, RefreshTokenRecord> _byId = {};
  final Map<String, String> _hashToId = {};

  @override
  Future<void> save(RefreshTokenRecord record) async {
    _byId[record.id] = record;
    _hashToId[record.tokenHash] = record.id;
  }

  @override
  Future<RefreshTokenRecord?> findByHash(String tokenHash) async {
    final id = _hashToId[tokenHash];
    if (id == null) return null;
    return _byId[id];
  }

  @override
  Future<void> revoke(String id, {String? replacedByTokenId}) async {
    final existing = _byId[id];
    if (existing == null) return;
    _byId[id] = RefreshTokenRecord(
      id: existing.id,
      userId: existing.userId,
      tokenHash: existing.tokenHash,
      expiresAt: existing.expiresAt,
      createdAt: existing.createdAt,
      revokedAt: DateTime.now().toUtc(),
      replacedByTokenId: replacedByTokenId,
      userAgent: existing.userAgent,
      ipAddress: existing.ipAddress,
    );
  }

  @override
  Future<void> revokeAllForUser(String userId) async {
    for (final entry in _byId.entries) {
      if (entry.value.userId == userId && entry.value.revokedAt == null) {
        await revoke(entry.key);
      }
    }
  }
}

class InMemoryAuditRepository implements AuditRepository {
  final List<AuditEvent> events = [];

  @override
  Future<void> append(AuditEvent event) async {
    events.add(event);
  }

  @override
  Future<List<AuditEvent>> listRecent({int limit = 50, String? actorUserId}) async {
    var list = events.reversed.toList();
    if (actorUserId != null) {
      list = list.where((e) => e.actorUserId == actorUserId).toList();
    }
    return list.take(limit).toList();
  }
}