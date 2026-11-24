import 'dart:convert';

import 'package:http/http.dart' as http;

import 'authenticated_api_client.dart';
import 'server_config_service.dart';

class SubscriptionStatus {
  const SubscriptionStatus({
    required this.plan,
    required this.chatUsed,
    required this.photoUsed,
    required this.chatLimit,
    required this.photoLimit,
    required this.resetsAt,
  });
  final String plan;
  final int chatUsed, photoUsed, chatLimit, photoLimit;
  final DateTime resetsAt;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'] as Map;
    final used = json['used'] as Map;
    return SubscriptionStatus(
      plan: json['plan'] as String,
      chatUsed: (used['chat'] as num).toInt(),
      photoUsed: (used['photo'] as num).toInt(),
      chatLimit: (limits['chat'] as num).toInt(),
      photoLimit: (limits['photo'] as num).toInt(),
      resetsAt: DateTime.parse(json['resets_at'] as String),
    );
  }
}

class SubscriptionApiService {
  SubscriptionApiService({http.Client? client, String? baseUrl})
    : _client = AuthenticatedApiClient(client: client),
      _base = Uri.parse(baseUrl ?? ServerConfigService.currentBaseUrl);
  final http.Client _client;
  final Uri _base;

  Future<SubscriptionStatus?> status() async {
    final response = await _client
        .get(_base.resolve('/subscription/me'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 401) return null;
    if (response.statusCode != 200) {
      throw Exception('Usage could not be loaded. Please try again.');
    }
    return SubscriptionStatus.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  Future<Map<String, dynamic>> billingConfiguration() async {
    final response = await _client
        .get(_base.resolve('/subscription/plans'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception(
        'Subscription checkout is unavailable. Please try again.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<SubscriptionStatus> verifyPlayPurchase(String purchaseToken) async {
    final response = await _client
        .post(
          _base.resolve('/subscription/google-play/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'purchase_token': purchaseToken}),
        )
        .timeout(const Duration(seconds: 35));
    if (response.statusCode != 200) {
      throw Exception(
        backendErrorMessage(response.body) ?? 'Payment verification could not finish. Please try Restore purchases.',
      );
    }
    final decoded = jsonDecode(response.body) as Map;
    if (decoded['verified'] != true) {
      throw Exception('Payment has not been verified yet.');
    }
    return SubscriptionStatus.fromJson(
      Map<String, dynamic>.from(decoded['subscription'] as Map),
    );
  }

  void close() => _client.close();
}
