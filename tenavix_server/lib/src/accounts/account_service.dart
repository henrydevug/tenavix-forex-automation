import 'dart:math';
import 'package:uuid/uuid.dart';
import '../common/types.dart';
import '../users/user.dart';
import '../auth/authorization.dart';
import '../licensing/bot_license.dart';
import '../subscriptions/subscription.dart';
import '../audit/audit_service.dart';
import 'trading_account.dart';

abstract class TradingAccountRepository {
  Future<TradingAccount?> findById(String id);
  Future<List<TradingAccount>> findByUserId(String userId);
  Future<TradingAccount?> findByBrokerDetails({
    required String userId,
    required String brokerAccountNumber,
    String? brokerServer,
  });
  Future<TradingAccount> create(TradingAccount account);
  Future<TradingAccount> update(TradingAccount account);
}

abstract class LicenseRepository {
  Future<BotLicense?> findByAccountId(String tradingAccountId);
  Future<BotLicense?> findByKey(String licenseKey);
  Future<BotLicense> create(BotLicense license);
  Future<BotLicense> update(BotLicense license);
}

abstract class SubscriptionRepository {
  Future<Subscription?> findActiveByAccountId(String tradingAccountId);
  Future<Subscription> create(Subscription sub);
  Future<Subscription> update(Subscription sub);
}

/// Manages trading accounts, auto-issues licenses, and creates subscription foundation.
/// Never stores or accepts broker passwords (ADR-001).
class AccountService {
  final TradingAccountRepository accounts;
  final LicenseRepository licenses;
  final SubscriptionRepository subscriptions;
  final AuditService audit;
  final _uuid = const Uuid();

  AccountService({
    required this.accounts,
    required this.licenses,
    required this.subscriptions,
    required this.audit,
  });

  /// Register a new MT5 trading account for the authenticated user.
  /// Automatically creates a BotLicense. Subscription starts as inactive until payment.
  Future<TradingAccount> registerAccount({
    required User caller,
    required String brokerAccountNumber,
    String? brokerServer,
    String? accountName,
    AccountEnvironment environment = AccountEnvironment.demo,
    String? currency,
  }) async {
    Authorization.requireAuthenticated(caller);

    if (brokerAccountNumber.trim().isEmpty) {
      throw const AppException(
        code: ErrorCodes.validation,
        message: 'Broker account number is required',
        statusCode: 400,
      );
    }

    final existing = await accounts.findByBrokerDetails(
      userId: caller.id,
      brokerAccountNumber: brokerAccountNumber.trim(),
      brokerServer: brokerServer?.trim(),
    );
    if (existing != null) {
      throw const AppException(
        code: ErrorCodes.conflict,
        message: 'This trading account is already registered',
        statusCode: 409,
      );
    }

    // Live accounts require extra future gates; for Sprint 2 we allow registration
    // but keep DEMO as the safe default (ADR-005).
    final now = DateTime.now().toUtc();
    final account = TradingAccount(
      id: _uuid.v4(),
      userId: caller.id,
      brokerAccountNumber: brokerAccountNumber.trim(),
      brokerServer: brokerServer?.trim(),
      accountName: accountName?.trim(),
      environment: environment,
      status: AccountStatus.active,
      currency: currency,
      createdAt: now,
      updatedAt: now,
    );

    final created = await accounts.create(account);

    // Auto-issue platform license (unique key)
    final licenseKey = _generateLicenseKey();
    final license = BotLicense(
      id: _uuid.v4(),
      tradingAccountId: created.id,
      licenseKey: licenseKey,
      status: LicenseStatus.active,
      issuedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await licenses.create(license);

    await audit.record(
      actorUserId: caller.id,
      action: 'account.register',
      resourceType: 'trading_account',
      resourceId: created.id,
      outcome: AuditOutcome.success,
      details: {
        'environment': environment.value,
        'licenseIssued': true,
      },
    );

    return created;
  }

  Future<List<TradingAccount>> listMyAccounts(User caller) async {
    Authorization.requireAuthenticated(caller);
    return accounts.findByUserId(caller.id);
  }

  Future<TradingAccount> getAccount({
    required User caller,
    required String accountId,
  }) async {
    final account = await accounts.findById(accountId);
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
    return account;
  }

  /// Validate license for EA. Returns structured result.
  /// Does NOT control customer funds (FR-025).
  Future<Map<String, dynamic>> validateLicense({
    required String licenseKey,
    required String brokerAccountNumber,
    String? eaInstanceId,
  }) async {
    final license = await licenses.findByKey(licenseKey);
    if (license == null) {
      return {
        'valid': false,
        'reason': 'LICENSE_NOT_FOUND',
      };
    }

    final account = await accounts.findById(license.tradingAccountId);
    if (account == null ||
        account.brokerAccountNumber != brokerAccountNumber ||
        account.status != AccountStatus.active) {
      return {
        'valid': false,
        'reason': 'ACCOUNT_MISMATCH_OR_INACTIVE',
      };
    }

    final sub = await subscriptions.findActiveByAccountId(account.id);
    final subscriptionActive = sub?.isActive ?? false;

    // Update last validated timestamp
    final updated = BotLicense(
      id: license.id,
      tradingAccountId: license.tradingAccountId,
      licenseKey: license.licenseKey,
      status: license.status,
      issuedAt: license.issuedAt,
      expiresAt: license.expiresAt,
      lastValidatedAt: DateTime.now().toUtc(),
      createdAt: license.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await licenses.update(updated);

    return updated.toValidationJson(subscriptionActive: subscriptionActive);
  }

  String _generateLicenseKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final parts = List.generate(4, (_) {
      return List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    });
    return 'TNX-${parts.join('-')}';
  }
}