import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../auth/auth_service.dart';
import '../auth/token_service.dart';
import '../auth/authorization.dart';
import '../accounts/account_service.dart';
import '../subscriptions/subscription_service.dart';
import '../users/admin_service.dart';
import '../users/user.dart';
import '../common/types.dart';

/// Lightweight HTTP API layer (Serverpod-compatible contract style).
/// Endpoints follow the logical contracts defined in the master specification.
class TenavixApi {
  final AuthService auth;
  final AccountService accounts;
  final SubscriptionService subscriptions;
  final AdminService admin;
  final TokenService tokenService;
  final UserRepository users;

  TenavixApi({
    required this.auth,
    required this.accounts,
    required this.subscriptions,
    required this.admin,
    required this.tokenService,
    required this.users,
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

    // Subscriptions
    r.post('/api/v1/subscriptions/activate', _activateSubscription);
    r.get('/api/v1/subscriptions/<accountId>', _getSubscription);

    // Admin
    r.post('/api/v1/admin/users/<id>/suspend', _suspendUser);

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
      return _json(201, account.toPublicJson());
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _listAccounts(Request req) async {
    try {
      final user = await _requireUser(req);
      final list = await accounts.listMyAccounts(user);
      return _json(200, {'accounts': list.map((a) => a.toPublicJson()).toList()});
    } on AppException catch (e) {
      return _error(e);
    }
  }

  Future<Response> _getAccount(Request req, String id) async {
    try {
      final user = await _requireUser(req);
      final account = await accounts.getAccount(caller: user, accountId: id);
      return _json(200, account.toPublicJson());
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