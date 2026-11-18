import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../auth/auth_service.dart';
import '../auth/token_service.dart';
import '../accounts/account_service.dart';
import '../subscriptions/subscription_service.dart';
import '../users/admin_service.dart';
import '../users/user.dart';
import '../common/types.dart';
import '../database/postgres_profit_share_repository.dart';

/// Lightweight HTTP API layer (Serverpod-compatible contract style).
/// Endpoints follow the logical contracts defined in the master specification.
class TenavixApi {
  final AuthService auth;
  final AccountService accounts;
  final SubscriptionService subscriptions;
  final AdminService admin;
  final TokenService tokenService;
  final UserRepository users;
  final PostgresProfitShareRepository profitShare;

  TenavixApi({
    required this.auth,
    required this.accounts,
    required this.subscriptions,
    required this.admin,
    required this.tokenService,
    required this.users,
    required this.profitShare,
  });

  Router get router {
    final r = Router();

    // Auth
    r.post('/api/v1/auth/register', _register);
    r.post('/api/v1/auth/login', _login);
    r.post('/api/v1/auth/refresh', _refresh);
    r.post('/api/v1/auth/logout', _logout);

    // Accounts
    r.post('/api/v1/accounts', _createAccount);
    r.get('/api/v1/accounts', _listAccounts);
    r.get('/api/v1/accounts/<id>', _getAccount);

    // Licenses (EA-facing — no user JWT required; validated by license key)
    r.post('/api/v1/licenses/validate', _validateLicense);
    r.post('/api/v1/ea/closed-deals', _ingestClosedDeal);

    // Profit-share billing and payment reconciliation
    r.post('/api/v1/billing/invoices/<invoiceId>/payments', _createBillingPayment);
    r.post('/api/v1/admin/billing/payments/<paymentId>/confirm', _confirmBankTransferPayment);

    // Subscriptions
    r.post('/api/v1/subscriptions/activate', _activateSubscription);
    r.get('/api/v1/subscriptions/<accountId>', _getSubscription);

    // Admin
    r.get('/api/v1/admin/users', _listUsers);
    r.post('/api/v1/admin/users/<id>/suspend', _suspendUser);
    r.get('/api/v1/admin/audit-events', _listAuditEvents);

    // Health
    r.get('/health', (Request req) => Response.ok(jsonEncode({'status': 'ok'})));

    return r;
  }

  Future<Response> _register(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final result = await auth.register(
        email: body['email'] as String? ?? '',
        password: body['password'] as String? ?? '',
        fullName: body['fullName'] as String?,
        ipAddress: req.headers['x-forwarded-for'],
        userAgent: req.headers['user-agent'],
      );
      return _json(201, {
        'user': result.user.toPublicJson(),
        'accessToken': result.accessToken,
        'refreshToken': result.refreshToken,
        'refreshExpiresAt': result.refreshExpiresAt.toIso8601String(),
      });
    } on AppException catch (e) {
      return _error(e);
    } catch (e) {
      return _json(500, {'code': ErrorCodes.internal, 'message': e.toString()});
    }
  }

  Future<Response> _login(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final result = await auth.login(
        email: body['email'] as String? ?? '',
        password: body['password'] as String? ?? '',
        ipAddress: req.headers['x-forwarded-for'],
        userAgent: req.headers['user-agent'],
      );
      return _json(200, {
        'user': result.user.toPublicJson(),
        'accessToken': result.accessToken,
        'refreshToken': result.refreshToken,
        'refreshExpiresAt': result.refreshExpiresAt.toIso8601String(),
      });
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _refresh(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final result = await auth.refresh(
        refreshToken: body['refreshToken'] as String? ?? '',
        ipAddress: req.headers['x-forwarded-for'],
        userAgent: req.headers['user-agent'],
      );
      return _json(200, {
        'user': result.user.toPublicJson(),
        'accessToken': result.accessToken,
        'refreshToken': result.refreshToken,
        'refreshExpiresAt': result.refreshExpiresAt.toIso8601String(),
      });
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _logout(Request req) async {
    try {
      final user = await _requireUser(req);
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
      await auth.logout(
        userId: user.id,
        refreshToken: body['refreshToken'] as String?,
        allSessions: body['allSessions'] == true,
      );
      return _json(200, {'ok': true});
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _createAccount(Request req) async {
    try {
      final user = await _requireUser(req);
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final envStr = (body['environment'] as String?) ?? 'demo';
      final account = await accounts.registerAccount(
        caller: user,
        brokerAccountNumber: body['brokerAccountNumber'] as String? ?? '',
        brokerServer: body['brokerServer'] as String?,
        accountName: body['accountName'] as String?,
        environment: AccountEnvironmentX.fromString(envStr),
        currency: body['currency'] as String?,
      );
      final payload = await accounts.accountPublicWithLicense(account);
      return _json(201, payload);
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _listAccounts(Request req) async {
    try {
      final user = await _requireUser(req);
      final list = await accounts.listMyAccounts(user);
      final enriched = <Map<String, dynamic>>[];
      for (final a in list) {
        enriched.add(await accounts.accountPublicWithLicense(a));
      }
      return _json(200, {'accounts': enriched});
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _getAccount(Request req, String id) async {
    try {
      final user = await _requireUser(req);
      final account = await accounts.getAccount(caller: user, accountId: id);
      return _json(200, await accounts.accountPublicWithLicense(account));
    } on AppException catch (e) {
      return _error(e);
    }
  }

  /// EA-facing: no user JWT. License key + account number only.
  Future<Response> _validateLicense(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final result = await accounts.validateLicense(
        licenseKey: body['licenseKey'] as String? ?? '',
        brokerAccountNumber: body['brokerAccountNumber'] as String? ?? '',
        eaInstanceId: body['eaInstanceId'] as String?,
      );
      return _json(200, result);
    } on AppException catch (e) {
      return _error(e);
    }
  }

  /// EA-facing closed-deal ingestion. The license is supplied as a bearer
  /// credential; account identity is resolved from the license, not request JSON.
  Future<Response> _ingestClosedDeal(Request req) async {
    try {
      final authorization = req.headers['authorization'] ?? '';
      if (!authorization.toLowerCase().startsWith('bearer ')) {
        return _json(401, {'code': ErrorCodes.licenseInvalid, 'message': 'Missing EA license credential.'});
      }
      final licenseKey = authorization.substring(7).trim();
      final decoded = jsonDecode(await req.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return _json(400, {'code': ErrorCodes.validation, 'message': 'Expected a JSON object.'});
      }
      final body = decoded;
      String requiredText(String key) {
        final value = body[key];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('Field "$key" is required as text.');
        }
        return value.trim();
      }
      String optionalMoney(String key) {
        final value = body[key];
        if (value == null) return '0';
        if (value is! String) {
          throw FormatException('Field "$key" must be a decimal string.');
        }
        return value;
      }

      final account = await profitShare.resolveLicensedAccount(
        licenseKey: licenseKey,
        brokerAccountNumber: requiredText('brokerAccountNumber'),
        brokerServer: requiredText('brokerServer'),
      );
      if (account == null) {
        return _json(401, {'code': ErrorCodes.licenseInvalid, 'message': 'License or registered MT5 account is invalid.'});
      }
      if (account['environment'] != 'demo') {
        return _json(403, {'code': ErrorCodes.forbidden, 'message': 'Closed-deal ingestion is DEMO-only until live release approval.'});
      }

      final currency = account['currency']!;
      final minorUnits = _currencyMinorUnits(currency);
      final dealTime = DateTime.tryParse(requiredText('dealTime'));
      if (dealTime == null) {
        throw const FormatException('dealTime must be an ISO-8601 timestamp.');
      }

      final result = await profitShare.recordClosedDeal(
        tradingAccountId: account['tradingAccountId']!,
        brokerDealId: requiredText('dealId'),
        symbol: requiredText('symbol'),
        dealTime: dealTime,
        currency: currency,
        currencyMinorUnits: minorUnits,
        profit: requiredText('profit'),
        commission: optionalMoney('commission'),
        swap: optionalMoney('swap'),
        brokerFee: optionalMoney('brokerFee'),
      );
      if (result == null) {
        return _json(200, {'accepted': true, 'duplicate': true});
      }
      return _json(202, {'accepted': true, 'duplicate': false, 'result': result});
    } on FormatException catch (e) {
      return _json(400, {'code': ErrorCodes.validation, 'message': e.message});
    } on ArgumentError catch (e) {
      return _json(400, {'code': ErrorCodes.validation, 'message': e.message});
    } on StateError catch (e) {
      return _json(409, {'code': ErrorCodes.conflict, 'message': e.message});
    } on AppException catch (e) {
      return _error(e);
    } catch (_) {
      return _json(500, {'code': ErrorCodes.internal, 'message': 'Unable to process closed deal.'});
    }
  }

  int _currencyMinorUnits(String currency) {
    const zeroDecimal = {'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF'};
    const threeDecimal = {'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'};
    if (zeroDecimal.contains(currency)) return 0;
    if (threeDecimal.contains(currency)) return 3;
    return 2;
  }

  Future<Response> _activateSubscription(Request req) async {
    try {
      final user = await _requireUser(req);
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final sub = await subscriptions.activateStandard(
        caller: user,
        tradingAccountId: body['tradingAccountId'] as String? ?? '',
      );
      return _json(201, sub.toPublicJson());
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _getSubscription(Request req, String accountId) async {
    try {
      final user = await _requireUser(req);
      final sub = await subscriptions.getActiveForAccount(
        caller: user,
        tradingAccountId: accountId,
      );
      return _json(200, sub?.toPublicJson() ?? {'active': false});
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _listUsers(Request req) async {
    try {
      final user = await _requireUser(req);
      final qp = req.url.queryParameters;
      final limit = int.tryParse(qp['limit'] ?? '') ?? 50;
      final offset = int.tryParse(qp['offset'] ?? '') ?? 0;
      final result = await admin.listUsers(
        caller: user,
        emailContains: qp['q'],
        status: qp['status'],
        limit: limit,
        offset: offset,
      );
      return _json(200, {
        'users': result.users.map((u) => u.toPublicJson()).toList(),
        'total': result.total,
        'limit': limit.clamp(1, 200),
        'offset': offset < 0 ? 0 : offset,
      });
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _listAuditEvents(Request req) async {
    try {
      final user = await _requireUser(req);
      final qp = req.url.queryParameters;
      final limit = int.tryParse(qp['limit'] ?? '') ?? 50;
      final events = await admin.listAuditEvents(
        caller: user,
        limit: limit,
        actorUserId: qp['actorUserId'],
      );
      return _json(200, {
        'events': events.map((e) => {
              'id': e.id,
              'actorUserId': e.actorUserId,
              'action': e.action,
              'resourceType': e.resourceType,
              'resourceId': e.resourceId,
              'outcome': e.outcome.name,
              'details': e.details,
              'createdAt': e.createdAt.toUtc().toIso8601String(),
            }).toList(),
      });
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _suspendUser(Request req, String id) async {
    try {
      final user = await _requireUser(req);
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
      await admin.suspendUser(
        caller: user,
        targetUserId: id,
        reason: body['reason'] as String?,
      );
      return _json(200, {'ok': true, 'userId': id, 'status': 'suspended'});
    } on AppException catch (e) {
      return _error(e);
    }
  }


  Future<Response> _createBillingPayment(Request req, String invoiceId) async {
    try {
      final user = await _requireUser(req);
      final decoded = jsonDecode(await req.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return _json(400, {'code': ErrorCodes.validation, 'message': 'Expected a JSON object.'});
      }
      final amount = decoded['amount'];
      final currency = decoded['currency'];
      final channel = decoded['channel'];
      final provider = decoded['provider'];
      final idempotencyKey = decoded['idempotencyKey'];
      if (amount is! String ||
          currency is! String ||
          channel is! String ||
          provider is! String ||
          idempotencyKey is! String) {
        return _json(400, {
          'code': ErrorCodes.validation,
          'message': 'amount, currency, channel, provider and idempotencyKey are required as strings.',
        });
      }
      final result = await profitShare.createPendingInvoicePayment(
        userId: user.id,
        invoiceId: invoiceId,
        amount: amount,
        currency: currency,
        channel: channel,
        provider: provider,
        idempotencyKey: idempotencyKey,
        payerReference: decoded['payerReference'] as String?,
      );
      return _json(201, result);
    } on AppException catch (e) {
      return _error(e);
    } on ArgumentError catch (e) {
      return _json(400, {'code': ErrorCodes.validation, 'message': e.message.toString()});
    } on StateError catch (e) {
      return _json(409, {'code': ErrorCodes.conflict, 'message': e.message});
    } catch (e) {
      return _json(500, {'code': ErrorCodes.internal, 'message': 'Unable to create payment.'});
    }
  }

  Future<Response> _confirmBankTransferPayment(
    Request req,
    String paymentId,
  ) async {
    try {
      final user = await _requireUser(req);
      if (!user.isAdmin) {
        return _json(403, {'code': ErrorCodes.forbidden, 'message': 'Administrator access required.'});
      }
      final decoded = jsonDecode(await req.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return _json(400, {'code': ErrorCodes.validation, 'message': 'Expected a JSON object.'});
      }
      final invoiceId = decoded['invoiceId'];
      final evidenceReference = decoded['evidenceReference'];
      if (invoiceId is! String || evidenceReference is! String) {
        return _json(400, {
          'code': ErrorCodes.validation,
          'message': 'invoiceId and evidenceReference are required as strings.',
        });
      }
      final result = await profitShare.confirmBankTransferPayment(
        paymentId: paymentId,
        invoiceId: invoiceId,
        actorUserId: user.id,
        evidenceReference: evidenceReference,
      );
      return _json(200, result);
    } on AppException catch (e) {
      return _error(e);
    } on ArgumentError catch (e) {
      return _json(400, {'code': ErrorCodes.validation, 'message': e.message.toString()});
    } on StateError catch (e) {
      return _json(409, {'code': ErrorCodes.conflict, 'message': e.message});
    } catch (e) {
      return _json(500, {'code': ErrorCodes.internal, 'message': 'Unable to confirm payment.'});
    }
  }

  Future<User> _requireUser(Request req) async {
    final header = req.headers['authorization'] ?? '';
    if (!header.toLowerCase().startsWith('bearer ')) {
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'Missing or invalid Authorization header',
        statusCode: 401,
      );
    }
    final token = header.substring(7).trim();
    try {
      final claims = tokenService.verifyAccessToken(token);
      final userId = claims['sub'] as String;
      final user = await users.findById(userId);
      if (user == null || !user.isActive) {
        throw const AppException(
          code: ErrorCodes.unauthorized,
          message: 'User inactive or not found',
          statusCode: 401,
        );
      }
      final roles = await users.getRoleNames(userId);
      return user.copyWith(roles: roles);
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        code: ErrorCodes.unauthorized,
        message: 'Invalid or expired access token',
        statusCode: 401,
      );
    }
  }

  Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  Response _error(AppException e) => _json(e.statusCode, {
        'code': e.code,
        'message': e.message,
        if (e.details != null) 'details': e.details,
      });
}