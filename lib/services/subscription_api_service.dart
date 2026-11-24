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

  void close() => _client.close();
}
