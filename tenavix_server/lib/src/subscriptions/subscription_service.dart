import 'package:uuid/uuid.dart';
import '../accounts/account_service.dart';
import '../audit/audit_service.dart';
import '../auth/authorization.dart';
import '../common/types.dart';
import '../users/user.dart';
import 'subscription.dart';

/// Activates / manages subscriptions for connected trading accounts.
class SubscriptionService {
  final SubscriptionRepository subscriptions;
  final TradingAccountRepository accounts;
  final AuditService audit;
  final _uuid = const Uuid();

  SubscriptionService({
    required this.subscriptions,
    required this.accounts,
    required this.audit,
  });

  /// Activate a standard subscription for a trading account (Sprint 2 foundation).
  /// In production this is called after verified payment webhook.
  /// For DEMO/testing we allow explicit activation by the account owner or admin.
  Future<Subscription> activateStandard({
    required User caller,
    required String tradingAccountId,
    int periodDays = 30,
  }) async {
    final account = await accounts.findById(tradingAccountId);
    if (account == null) {
      throw const AppException(
        code: ErrorCodes.notFound,
        message: 'Trading account not found',
        statusCode: 404,
      );
    }
    Authorization.requireOwnershipOrAdmin(
      caller: caller,
      resourceOwnerId: account.userId,
    );

    final existing = await subscriptions.findActiveByAccountId(tradingAccountId);
    if (existing != null && existing.isActive) {
      throw const AppException(
        code: ErrorCodes.conflict,
        message: 'An active subscription already exists for this account',
        statusCode: 409,
      );
    }

    final now = DateTime.now().toUtc();
    final plan = PricingPlan.standardV1;
    final sub = Subscription(
      id: _uuid.v4(),
      tradingAccountId: tradingAccountId,
      planCode: plan.code,
      status: SubscriptionStatus.active,
      currentPeriodStart: now,
      currentPeriodEnd: now.add(Duration(days: periodDays)),
      createdAt: now,
      updatedAt: now,
    );

    final created = await subscriptions.create(sub);

    await audit.record(
      actorUserId: caller.id,
      action: 'subscription.activate',
      resourceType: 'subscription',
      resourceId: created.id,
      outcome: AuditOutcome.success,
      details: {
        'tradingAccountId': tradingAccountId,
        'planCode': plan.code,
        'periodDays': periodDays,
      },
    );

    return created;
  }

  Future<Subscription?> getActiveForAccount({
    required User caller,
    required String tradingAccountId,
  }) async {
    final account = await accounts.findById(tradingAccountId);
    if (account == null) {
      throw const AppException(
        code: ErrorCodes.notFound,
        message: 'Trading account not found',
        statusCode: 404,
      );
    }
    Authorization.requireOwnershipOrAdmin(
      caller: caller,
      resourceOwnerId: account.userId,
    );
    return subscriptions.findActiveByAccountId(tradingAccountId);
  }
}