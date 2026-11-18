import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// MTN MoMo Uganda Collections client.
///
/// Credentials are read only from environment variables. This client never
/// handles disbursements. Sandbox is the safe default.
class MtnMomoClient {
  final http.Client _http;
  final String baseUrl;
  final String targetEnvironment;
  final String userId;
  final String credentialToken;
  final String subscriptionKey;
  String? _accessToken;
  DateTime? _tokenExpiresAt;

  MtnMomoClient({
    http.Client? httpClient,
    String? baseUrl,
    String? targetEnvironment,
    String? userId,
    String? credentialToken,
    String? subscriptionKey,
  })  : _http = httpClient ?? http.Client(),
        baseUrl = (baseUrl ??
                Platform.environment['MTN_MOMO_BASE_URL'] ??
                'https://sandbox.momodeveloper.mtn.com')
            .replaceAll(RegExp(r'/+$'), ''),
        targetEnvironment = targetEnvironment ??
            Platform.environment['MTN_MOMO_TARGET_ENVIRONMENT'] ??
            'sandbox',
        userId = userId ?? Platform.environment['MTN_MOMO_USER_ID'] ?? '',
        credentialToken = credentialToken ??
            Platform.environment['MTN_MOMO_CREDENTIAL_TOKEN'] ??
            '',
        subscriptionKey = subscriptionKey ??
            Platform.environment['MTN_MOMO_SUBSCRIPTION_KEY'] ??
            '';

  factory MtnMomoClient.fromEnvironment({http.Client? httpClient}) =>
      MtnMomoClient(httpClient: httpClient);

  bool get isConfigured =>
      baseUrl.startsWith('https://') &&
      userId.isNotEmpty &&
      credentialToken.isNotEmpty &&
      subscriptionKey.isNotEmpty &&
      targetEnvironment.isNotEmpty;

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<String> _token() async {
    if (!isConfigured) {
      throw StateError('MTN MoMo credentials are not configured.');
    }
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now()
            .toUtc()
            .isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 2)))) {
      return _accessToken!;
    }

    final basic = base64Encode(utf8.encode('$userId:$credentialToken'));
    final response = await _http.post(
      Uri.parse('$baseUrl/collection/token'),
      headers: {
        'Authorization': 'Basic $basic',
        'Ocp-Apim-Subscription-Key': subscriptionKey,
        'X-Target-Environment': targetEnvironment,
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw StateError(
          'MTN token request failed with HTTP ${response.statusCode}.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw StateError('MTN token response did not contain access_token.');
    }
    final expiresIn =
        int.tryParse(data['expires_in']?.toString() ?? '') ?? 3600;
    _accessToken = token;
    _tokenExpiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    return token;
  }

  String newReferenceId() => _uuidV4();

  Future<void> requestToPay({
    required String referenceId,
    required String amount,
    required String currency,
    required String phoneNumber,
    required String externalId,
    required String payerMessage,
  }) async {
    final token = await _token();
    final response = await _http
        .post(
          Uri.parse('$baseUrl/collection/v1_0/requesttopay'),
          headers: {
            'Authorization': 'Bearer $token',
            'Ocp-Apim-Subscription-Key': subscriptionKey,
            'X-Target-Environment': targetEnvironment,
            'X-Reference-Id': referenceId,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'amount': amount,
            'currency': currency,
            'externalId': externalId,
            'payer': {'partyIdType': 'MSISDN', 'partyId': phoneNumber},
            'payerMessage': payerMessage,
            'payeeNote': 'Tenavix invoice payment',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 202) {
      throw StateError(
          'MTN RequestToPay was not accepted (HTTP ${response.statusCode}).');
    }
  }

  Future<Map<String, dynamic>> getPaymentStatus(String referenceId) async {
    final token = await _token();
    final response = await _http.get(
      Uri.parse('$baseUrl/collection/v1_0/requesttopay/$referenceId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Ocp-Apim-Subscription-Key': subscriptionKey,
        'X-Target-Environment': targetEnvironment,
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError(
          'MTN status lookup failed with HTTP ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void close() => _http.close();
}
