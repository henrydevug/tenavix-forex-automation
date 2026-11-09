import 'package:uuid/uuid.dart';
import '../common/types.dart';

class AuditEvent {
  final String id;
  final String? actorUserId;
  final String action;
  final String? resourceType;
  final String? resourceId;
  final AuditOutcome outcome;
  final Map<String, dynamic>? details;
  final String? ipAddress;
  final String? userAgent;
  final DateTime createdAt;

  AuditEvent({
    required this.id,
    this.actorUserId,
    required this.action,
    this.resourceType,
    this.resourceId,
    required this.outcome,
    this.details,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
  });
}

abstract class AuditRepository {
  Future<void> append(AuditEvent event);
  Future<List<AuditEvent>> listRecent({int limit = 50, String? actorUserId});
}

class AuditService {
  final AuditRepository repository;
  final _uuid = const Uuid();

  AuditService(this.repository);

  Future<void> record({
    String? actorUserId,
    required String action,
    String? resourceType,
    String? resourceId,
    required AuditOutcome outcome,
    Map<String, dynamic>? details,
    String? ipAddress,
    String? userAgent,
  }) async {
    final event = AuditEvent(
      id: _uuid.v4(),
      actorUserId: actorUserId,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      outcome: outcome,
      details: details,
      ipAddress: ipAddress,
      userAgent: userAgent,
      createdAt: DateTime.now().toUtc(),
    );
    await repository.append(event);
  }

  Future<List<AuditEvent>> listRecent({
    int limit = 50,
    String? actorUserId,
  }) {
    return repository.listRecent(limit: limit, actorUserId: actorUserId);
  }
}