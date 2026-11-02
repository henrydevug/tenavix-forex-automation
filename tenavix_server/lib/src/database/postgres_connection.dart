import 'package:postgres/postgres.dart';

/// Central PostgreSQL connection factory.
/// Connection string is supplied via environment (never hard-coded secrets in production).
class PostgresPool {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  Connection? _conn;

  PostgresPool({
    this.host = 'localhost',
    this.port = 5432,
    this.database = 'tenavix',
    this.username = 'tenavix',
    this.password = 'tenavix_dev_secret',
  });

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