import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:uuid/uuid.dart';

/// Issues and validates JWT access tokens + opaque refresh tokens.
/// Refresh tokens are rotated on every use (refresh-token rotation).
class TokenService {
  final String jwtSecret;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;
  final _uuid = const Uuid();

  TokenService({
    required this.jwtSecret,
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 7),
  });

  /// Create a short-lived access token containing user identity and roles.
  String createAccessToken({
    required String userId,
    required String email,
    required List<String> roles,
  }) {
    final jwt = JWT(
      {
        'sub': userId,
        'email': email,
        'roles': roles,
        'type': 'access',
      },
      issuer: 'tenavix',
    );
    return jwt.sign(
      SecretKey(jwtSecret),
      expiresIn: accessTokenTtl,
      algorithm: JWTAlgorithm.HS256,
    );
  }

  /// Create an opaque refresh token (stored hashed server-side).
  String createRefreshTokenValue() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String newRefreshTokenId() => _uuid.v4();

  /// Verify access token and return claims. Throws on invalid/expired.
  Map<String, dynamic> verifyAccessToken(String token) {
    final jwt = JWT.verify(token, SecretKey(jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    if (payload['type'] != 'access') {
      throw JWTException('Invalid token type');
    }
    return payload;
  }

  /// Hash a refresh token for storage (never store raw).
  String hashRefreshToken(String rawToken) {
    final bytes = utf8.encode(rawToken);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes);
  }
}

/// DB representation of a refresh token record.
class RefreshTokenRecord {
  final String id;
  final String userId;
  final String tokenHash;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final String? replacedByTokenId;
  final String? userAgent;
  final String? ipAddress;

  RefreshTokenRecord({
    required this.id,
    required this.userId,
    required this.tokenHash,
    required this.expiresAt,
    required this.createdAt,
    this.revokedAt,
    this.replacedByTokenId,
    this.userAgent,
    this.ipAddress,
  });

  bool get isValid =>
      revokedAt == null && expiresAt.isAfter(DateTime.now().toUtc());
}