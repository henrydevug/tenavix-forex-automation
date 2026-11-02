import '../accounts/account_service.dart';
import '../accounts/trading_account.dart';
import '../licensing/bot_license.dart';
import '../subscriptions/subscription.dart';

class InMemoryTradingAccountRepository implements TradingAccountRepository {
  final Map<String, TradingAccount> _byId = {};

  @override
  Future<TradingAccount?> findById(String id) async => _byId[id];

  @override
  Future<List<TradingAccount>> findByUserId(String userId) async {
    return _byId.values.where((a) => a.userId == userId).toList();
  }

  @override
  Future<TradingAccount?> findByBrokerDetails({
    required String userId,
    required String brokerAccountNumber,
    String? brokerServer,
  }) async {
    try {
      return _byId.values.firstWhere(
        (a) =>
            a.userId == userId &&
            a.brokerAccountNumber == brokerAccountNumber &&
            (a.brokerServer ?? '') == (brokerServer ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TradingAccount> create(TradingAccount account) async {
    _byId[account.id] = account;
    return account;
  }

  @override
  Future<TradingAccount> update(TradingAccount account) async {
    _byId[account.id] = account;
    return account;
  }
}

class InMemoryLicenseRepository implements LicenseRepository {
  final Map<String, BotLicense> _byId = {};
  final Map<String, String> _keyToId = {};
  final Map<String, String> _accountToId = {};

  @override
  Future<BotLicense?> findByAccountId(String tradingAccountId) async {
    final id = _accountToId[tradingAccountId];
    if (id == null) return null;
    return _byId[id];
  }

  @override
  Future<BotLicense?> findByKey(String licenseKey) async {
    final id = _keyToId[licenseKey];
    if (id == null) return null;
    return _byId[id];
  }

  @override
  Future<BotLicense> create(BotLicense license) async {
    _byId[license.id] = license;
    _keyToId[license.licenseKey] = license.id;
    _accountToId[license.tradingAccountId] = license.id;
    return license;
  }

  @override
  Future<BotLicense> update(BotLicense license) async {
    _byId[license.id] = license;
    return license;
  }
}

class InMemorySubscriptionRepository implements SubscriptionRepository {
  final Map<String, Subscription> _byId = {};
  final Map<String, String> _accountToActiveId = {};

  @override
  Future<Subscription?> findActiveByAccountId(String tradingAccountId) async {
    final id = _accountToActiveId[tradingAccountId];
    if (id == null) return null;
    final sub = _byId[id];
    if (sub == null || !sub.isActive) return null;
    return sub;
  }

  @override
  Future<Subscription> create(Subscription sub) async {
    _byId[sub.id] = sub;
    if (sub.isActive) {
      _accountToActiveId[sub.tradingAccountId] = sub.id;
    }
    return sub;
  }

  @override
  Future<Subscription> update(Subscription sub) async {
    _byId[sub.id] = sub;
    if (sub.isActive) {
      _accountToActiveId[sub.tradingAccountId] = sub.id;
    } else {
      _accountToActiveId.remove(sub.tradingAccountId);
    }
    return sub;
  }
}