import 'dart:convert';

import 'package:culinary_ai/services/authenticated_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('backend requests include the current Firebase token', () async {
    final client = AuthenticatedApiClient(
      tokenProvider: () async => 'verified-token',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer verified-token');
        return http.Response('{}', 200);
      }),
    );
    await client.get(Uri.parse('https://backend.test/subscription/me'));
    client.close();
  });

  test(
    'monthly quota generates an upgrade notice and preserves response details',
    () async {
      final notices = <QuotaLimitNotice>[];
      final subscription = SubscriptionEvents.limits.stream.listen(notices.add);
      final body = jsonEncode({
        'detail': {
          'code': 'quota_exceeded',
          'kind': 'photo',
          'plan': 'free',
          'message': 'Your monthly photo scan allowance is used up.',
          'resets_at': '2026-12-01T00:00:00Z',
        },
      });
      final client = AuthenticatedApiClient(
        tokenProvider: () async => null,
        client: MockClient(
          (_) async =>
              http.Response(body, 429, headers: {'x-usage-limit': 'exceeded'}),
        ),
      );
      final response = await client.post(
        Uri.parse('https://backend.test/parse-receipt'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(response.body, body);
      expect(notices.single.kind, 'photo');
      expect(notices.single.resetsAt, DateTime.utc(2026, 12));
      expect(
        backendErrorMessage(response.body),
        'Your monthly photo scan allowance is used up.',
      );
      await subscription.cancel();
      client.close();
    },
  );

  test(
    'Groq rate-limit responses do not trigger a subscription prompt',
    () async {
      final notices = <QuotaLimitNotice>[];
      final subscription = SubscriptionEvents.limits.stream.listen(notices.add);
      final client = AuthenticatedApiClient(
        tokenProvider: () async => null,
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'detail': 'Groq is busy'}), 429),
        ),
      );
      final response = await client.get(
        Uri.parse('https://backend.test/chef-chat'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(notices, isEmpty);
      expect(backendErrorMessage(response.body), 'Groq is busy');
      await subscription.cancel();
      client.close();
    },
  );
}
