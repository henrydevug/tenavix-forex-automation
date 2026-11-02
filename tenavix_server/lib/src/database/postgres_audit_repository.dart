import 'dart:convert';
import 'package:postgres/postgres.dart';
import '../audit/audit_service.dart';
import '../common/types.dart';
import 'postgres_connection.dart';

class PostgresAuditRepository implements AuditRepository {
  final PostgresPool pool;
  PostgresAuditRepository(this.pool);

  @override
  Future<void> append(AuditEvent event) async {
    final conn = await pool.connection;
    await conn.execute(
      Sql.named(
        'INSERT INTO audit_events '
        '(id, actor_user_id, action, resource_type, resource_id, outcome, details, ip_address, user_agent, created_at) '
        'VALUES (@id::uuid, @actor::uuid, @action, @rtype, @rid, @outcome, @details::jsonb, @ip::inet, @ua, @created)',
      ),
      parameters: {
        'id': event.id,
        'actor': event.actorUserId,
        'action': event.action,
        'rtype': event.resourceType,
        'rid': event.resourceId,
        'outcome': event.outcome.name,
        'details': event.details != null ? jsonEncode(event.details) : null,
        'ip': event.ipAddress,
        'ua': event.userAgent,
        'created': event.createdAt.toUtc(),
      },
    );
  }

  @override
  Future<List<AuditEvent>> listRecent({int limit = 50, String? actorUserId}) async {
    final conn = await pool.connection;
    final Result result;
    if (actorUserId != null) {
      result = await conn.execute(
        Sql.named(
          'SELECT id, actor_user_id, action, resource_type, resource_id, outcome, details, '
          'ip_address::text, user_agent, created_at FROM audit_events '
          'WHERE actor_user_id = @actor::uuid ORDER BY created_at DESC LIMIT @lim',
        ),
        parameters: {'actor': actorUserId, 'lim': limit},
      );
    } else {
      result = await conn.execute(
        Sql.named(
          'SELECT id, actor_user_id, action, resource_type, resource_id, outcome, details, '
          'ip_address::text, user_agent, created_at FROM audit_events '
          'ORDER BY created_at DESC LIMIT @lim',
        ),
        parameters: {'lim': limit},
      );
    }
    return result.map((r) {
      return AuditEvent(
        id: r[0].toString(),
        actorUserId: r[1]?.toString(),
        action: r[2] as String,
        resourceType: r[3] as String?,
        resourceId: r[4] as String?,
        outcome: (r[5] as String) == 'success' ? AuditOutcome.success : AuditOutcome.failure,
        details: r[6] is Map ? Map<String, dynamic>.from(r[6] as Map) : null,
        ipAddress: r[7] as String?,
        userAgent: r[8] as String?,
        createdAt: (r[9] as DateTime).toUtc(),
      );
    }).toList();
  }
}