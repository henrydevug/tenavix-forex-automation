import 'package:equatable/equatable.dart';
import '../common/types.dart';

/// Subscription attached to a TradingAccount.
/// Active subscription is required for automated trade entries (FR-031).
class Subscription extends Equatable {
  final String id;
  final String tradingAccountId;
  final String planCode;
  final SubscriptionStatus status;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Subscription({
    required this.id,
    required this.tradingAccountId,
    required this.planCode,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive =>
      status == SubscriptionStatus.active &&
      currentPeriodEnd.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'tradingAccountId': tradingAccountId,
        'planCode': planCode,
        'status': status.value,
        'currentPeriodStart': currentPeriodStart.toUtc().toIso8601String(),
        'currentPeriodEnd': currentPeriodEnd.toUtc().toIso8601String(),
        'cancelAtPeriodEnd': cancelAtPeriodEnd,
        'cancelledAt': cancelledAt?.toUtc().toIso8601String(),
        'isActive': isActive,
      };

  @override
  List<Object?> get props => [id, tradingAccountId, planCode, status];
}

/// Simple pricing plan definition (extensible pricing engine foundation).
class PricingPlan {
  final String code;
  final String name;
  final int amountCents;
  final String currency;
  final int intervalDays;

  const PricingPlan({
    required this.code,
    required this.name,
    required this.amountCents,
    this.currency = 'USD',
    this.intervalDays = 30,
  });

  static const standardV1 = PricingPlan(
    code: 'standard_v1',
    name: 'Standard (per connected account)',
    amountCents: 200, // USD 2.00
    currency: 'USD',
    intervalDays: 30,
  );

  static PricingPlan? byCode(String code) {
    if (code == standardV1.code) return standardV1;
    return null;
  }
}