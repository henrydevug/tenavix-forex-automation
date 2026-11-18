import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tenavix_server/src/payments/mtn_momo_client.dart';
import 'package:test/test.dart';

String? _header(http.Request request, String name) {
  final key = name.toLowerCase();
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == key) return entry.value;
  }
  return null;
}

void main() {
  group('MtnMomoClient', () {
    test('requests a token using migrated Uganda credential headers', () async {
      var tokenRequested = false;
      final client = MtnMomoClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/collection/token') {
            tokenRequested = true;
            expect(_header(request, 'X-Target-Environment'), 'mtnuganda');
            expect(_header(request, 'Ocp-Apim-Subscription-Key'), 'subscription');
            expect(_header(request, 'Authorization'), startsWith('Basic '));
            return http.Response(
              jsonEncode({'access_token': 'test-token', 'expires_in': 3600}),
              200,
            );
          }
          expect(request.url.path, '/collection/v1_0/requesttopay');
          expect(request.headers['X-Target-Environment'], 'mtnuganda');
          return http.Response('', 202);
        }),
        baseUrl: 'https://momoapi.momo.africa',
        targetEnvironment: 'mtnuganda',
        userId: 'test-user',
        credentialToken: 'test-credential',
        subscriptionKey: 'subscription',
      );

      final reference = client.newReferenceId();
      await client.requestToPay(
        referenceId: reference,
        amount: '10000',
        currency: 'UGX',
        phoneNumber: '256770000001',
        externalId: '00000000-0000-4000-8000-000000000001',
        payerMessage: 'Tenavix invoice payment',
      );
      expect(tokenRequested, isTrue);
      client.close();
    });

    test('sends a RequestToPay and requires HTTP 202', () async {
      var tokenCalls = 0;
      var requestCalls = 0;
      final client = MtnMomoClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/collection/token') {
            tokenCalls++;
            return http.Response(
              jsonEncode({'access_token': 'test-token', 'expires_in': 3600}),
              200,
            );
          }
          requestCalls++;
          expect(request.url.path, '/collection/v1_0/requesttopay');
          expect(_header(request, 'Authorization'), 'Bearer test-token');
          expect(request.headers['X-Target-Environment'], 'mtnuganda');
          expect(_header(request, 'X-Reference-Id'), matches(
            RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
          ));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['currency'], 'UGX');
          expect(body['payer']['partyId'], '256770000001');
          expect(body['externalId'], 'payment-1');
          return http.Response('', 202);
        }),
        baseUrl: 'https://sandbox.momodeveloper.mtn.com',
        targetEnvironment: 'sandbox',
        userId: 'test-user',
        credentialToken: 'test-credential',
        subscriptionKey: 'subscription',
      );

      await client.requestToPay(
        referenceId: client.newReferenceId(),
        amount: '15000',
        currency: 'UGX',
        phoneNumber: '256770000001',
        externalId: 'payment-1',
        payerMessage: 'Invoice payment',
      );
      expect(tokenCalls, 1);
      expect(requestCalls, 1);
      client.close();
    });

    test('reads provider status without treating callback data as authority', () async {
      final client = MtnMomoClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/collection/token') {
            return http.Response(
              jsonEncode({'access_token': 'test-token', 'expires_in': 3600}),
              200,
            );
          }
          expect(request.method, 'GET');
          expect(request.url.path, '/collection/v1_0/requesttopay/ref-123');
          return http.Response(
            jsonEncode({
              'externalId': 'payment-1',
              'amount': '15000',
              'currency': 'UGX',
              'status': 'PENDING',
            }),
            200,
          );
        }),
        baseUrl: 'https://sandbox.momodeveloper.mtn.com',
        targetEnvironment: 'sandbox',
        userId: 'test-user',
        credentialToken: 'test-credential',
        subscriptionKey: 'subscription',
      );

      final status = await client.getPaymentStatus('ref-123');
      expect(status['status'], 'PENDING');
      client.close();
    });
  });
}
