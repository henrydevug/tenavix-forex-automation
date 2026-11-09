import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:tenavix_server/src/api/http_api.dart';
import 'package:tenavix_server/src/auth/auth_service.dart';
import 'package:tenavix_server/src/auth/password_hasher.dart';
import 'package:tenavix_server/src/auth/token_service.dart';
import 'package:tenavix_server/src/audit/audit_service.dart';
import 'package:tenavix_server/src/accounts/account_service.dart';
import 'package:tenavix_server/src/subscriptions/subscription_service.dart';
import 'package:tenavix_server/src/users/admin_service.dart';
import 'package:tenavix_server/src/database/postgres_connection.dart';
import 'package:tenavix_server/src/database/postgres_user_repository.dart';
import 'package:tenavix_server/src/database/postgres_account_repository.dart';
import 'package:tenavix_server/src/database/postgres_audit_repository.dart';

/// Local development HTTP entrypoint with CORS for the tenavix_web client.
Future<void> main(List<String> args) async {
  final jwtSecret = Platform.environment['TENAVIX_JWT_SECRET'];
  if (jwtSecret == null || jwtSecret.length < 32) {
    stderr.writeln('TENAVIX_JWT_SECRET must be set (min 32 characters).');
    exit(1);
  }

  final pool = PostgresPool.fromEnvironment();
  final userRepo = PostgresUserRepository(pool);
  final refreshRepo = PostgresRefreshTokenRepository(pool);
  final accountRepo = PostgresTradingAccountRepository(pool);
  final licenseRepo = PostgresLicenseRepository(pool);
  final subRepo = PostgresSubscriptionRepository(pool);
  final auditRepo = PostgresAuditRepository(pool);

  final tokenService = TokenService(jwtSecret: jwtSecret);
  final passwordHasher = PasswordHasher();
  final audit = AuditService(auditRepo);

  final auth = AuthService(
    users: userRepo,
    refreshTokens: refreshRepo,
    passwordHasher: passwordHasher,
    tokenService: tokenService,
    audit: audit,
  );
  final accounts = AccountService(
    accounts: accountRepo,
    licenses: licenseRepo,
    subscriptions: subRepo,
    audit: audit,
  );
  final subscriptions = SubscriptionService(
    subscriptions: subRepo,
    accounts: accountRepo,
    audit: audit,
  );
  final admin = AdminService(
    users: userRepo,
    postgresUsers: userRepo,
    refreshTokens: refreshRepo,
    audit: audit,
  );

  final api = TenavixApi(
    auth: auth,
    accounts: accounts,
    subscriptions: subscriptions,
    admin: admin,
    tokenService: tokenService,
    users: userRepo,
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(api.router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Tenavix API listening on http://${server.address.host}:$port',
  );
}

Middleware _cors() {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers':
        'Origin, Content-Type, Authorization, Accept',
  };
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: {...response.headers, ...headers});
    };
  };
}
