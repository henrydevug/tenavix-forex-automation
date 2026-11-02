import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:argon2/argon2.dart';

/// Secure password hashing using Argon2id.
/// Parameters chosen for interactive login (OWASP recommendations baseline).
class PasswordHasher {
  static const int _saltLength = 16;
  static const int _hashLength = 32;
  static const int _iterations = 3;
  static const int _memory = 65536; // 64 MB
  static const int _parallelism = 4;

  final Argon2BytesGenerator _generator;

  PasswordHasher() : _generator = Argon2BytesGenerator() {
    // Configured per call for clarity.
  }

  /// Returns a PHC-style encoded string: $argon2id$v=19$m=65536,t=3,p=4$salt$hash
  String hash(String password) {
    final salt = _randomBytes(_saltLength);
    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: _iterations,
      memory: _memory,
      lanes: _parallelism,
    );

    _generator.init(parameters);
    final hashBytes = Uint8List(_hashLength);
    _generator.generateBytes(
      utf8.encode(password),
      hashBytes,
      0,
      hashBytes.length,
    );

    final saltB64 = base64Url.encode(salt).replaceAll('=', '');
    final hashB64 = base64Url.encode(hashBytes).replaceAll('=', '');

    return '\$argon2id\$v=19\$m=$_memory,t=$_iterations,p=$_parallelism\$$saltB64\$$hashB64';
  }

  /// Constant-time verification.
  bool verify(String password, String encodedHash) {
    try {
      final parts = encodedHash.split('\$');
      // Expected: ['', 'argon2id', 'v=19', 'm=...,t=...,p=...', salt, hash]
      if (parts.length < 6 || parts[1] != 'argon2id') return false;

      final paramsPart = parts[3];
      final saltB64 = parts[4];
      final hashB64 = parts[5];

      int memory = _memory;
      int iterations = _iterations;
      int parallelism = _parallelism;

      for (final p in paramsPart.split(',')) {
        if (p.startsWith('m=')) memory = int.parse(p.substring(2));
        if (p.startsWith('t=')) iterations = int.parse(p.substring(2));
        if (p.startsWith('p=')) parallelism = int.parse(p.substring(2));
      }

      // Restore padding for base64Url
      final salt = base64Url.decode(_pad(saltB64));
      final expectedHash = base64Url.decode(_pad(hashB64));

      final parameters = Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        version: Argon2Parameters.ARGON2_VERSION_13,
        iterations: iterations,
        memory: memory,
        lanes: parallelism,
      );

      _generator.init(parameters);
      final computed = Uint8List(expectedHash.length);
      _generator.generateBytes(
        utf8.encode(password),
        computed,
        0,
        computed.length,
      );

      return _constantTimeEquals(computed, expectedHash);
    } catch (_) {
      return false;
    }
  }

  static String _pad(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s + ('=' * (4 - mod));
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rnd.nextInt(256)));
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}