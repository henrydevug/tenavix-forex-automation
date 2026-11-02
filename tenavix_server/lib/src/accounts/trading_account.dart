import 'package:equatable/equatable.dart';
import '../common/types.dart';

/// A connected MT5 trading account belonging to a platform User.
/// Distinct from the platform user account (ADR-001 / domain separation).
class TradingAccount extends Equatable {
  final String id;
  final String userId;
  final String brokerAccountNumber;
  final String? brokerServer;
  final String? accountName;
  final AccountEnvironment environment;
  final AccountStatus status;
  final String? currency;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TradingAccount({
    required this.id,
    required this.userId,
    required this.brokerAccountNumber,
    this.brokerServer,
    this.accountName,
    required this.environment,
    required this.status,
    this.currency,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDemo => environment == AccountEnvironment.demo;
  bool get isLive => environment == AccountEnvironment.live;
  bool get isActive => status == AccountStatus.active;

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'userId': userId,
        'brokerAccountNumber': brokerAccountNumber,
        'brokerServer': brokerServer,
        'accountName': accountName,
        'environment': environment.value,
        'status': status.value,
        'currency': currency,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  @override
  List<Object?> get props => [id, userId, brokerAccountNumber, environment, status];
}