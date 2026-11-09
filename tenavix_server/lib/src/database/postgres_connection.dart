import 'dart:io';

import 'package:postgres/postgres.dart';

/// Central PostgreSQL connection factory.
///
/// Credentials are loaded from environment variables. There is no silent
/// production default password. Local development may set:
///   TENAVIX_DB_HOST, TENAVIX_DB_PORT, TENAVIX_DB_NAME,
///   TENAVIX_DB_USER, TENAVIX_DB_PASSWORD
class PostgresPool {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  Connection? _conn;

  PostgresPool({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  /// Build a pool from environment variables.
  ///
  /// Required: [TENAVIX_DB_PASSWORD]
  /// Optional: TENAVIX_DB_HOST (localhost), TENAVIX_DB_PORT (5432),
  ///           TENAVIX_DB_NAME (tenavix), TENAVIX_DB_USER (tenavix)
  factory PostgresPool.fromEnvironment() {
    final password = Platform.environment['TENAVIX_DB_PASSWORD'];
    if (password == null || password.isEmpty) {
      throw StateError(
        'TENAVIX_DB_PASSWORD is required. '
        'Set database credentials via environment variables.',
      );
    }
    return PostgresPool(
      host: Platform.environment['TENAVIX_DB_HOST'] ?? 'localhost',
      port: int.tryParse(Platform.environment['TENAVIX_DB_PORT'] ?? '') ?? 5432,
      database: Platform.environment['TENAVIX_DB_NAME'] ?? 'tenavix',
      username: Platform.environment['TENAVIX_DB_USER'] ?? 'tenavix',
      password: password,
    );
  }

  Future<Connection> get connection async {
    if (_conn != null) return _conn!;
    _conn = await Connection.open(
      Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    return _conn!;
  }

  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }
}
