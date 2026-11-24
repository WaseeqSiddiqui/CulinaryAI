import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'firebase_service.dart';

class QuotaLimitNotice {
  const QuotaLimitNotice({
    required this.kind,
    required this.plan,
    required this.message,
    this.resetsAt,
  });
  final String kind;
  final String plan;
  final String message;
  final DateTime? resetsAt;
}

class SubscriptionEvents {
  static final limits = StreamController<QuotaLimitNotice>.broadcast();
}

String? backendErrorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final detail = decoded['detail'];
    if (detail is String) return detail;
    if (detail is Map && detail['message'] is String) {
      return detail['message'] as String;
    }
  } catch (_) {}
  return null;
}

/// Firebase identity is verified on the backend; a user-id form field is not proof.
class AuthenticatedApiClient extends http.BaseClient {
  AuthenticatedApiClient({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  static Future<String?> _firebaseToken() async {
    if (!FirebaseService.isInitialized) return null;
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _tokenProvider();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await _client.send(request);
    // A provider capacity error must never be confused with this user's quota.
    if (response.statusCode != 429 ||
        response.headers['x-usage-limit'] != 'exceeded') {
      return response;
    }
    final bytes = await response.stream.toBytes();
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is Map && detail['code'] == 'quota_exceeded') {
        SubscriptionEvents.limits.add(
          QuotaLimitNotice(
            kind: detail['kind'] as String? ?? 'chat',
            plan: detail['plan'] as String? ?? 'free',
            message:
                detail['message'] as String? ??
                'Your monthly allowance is used up.',
            resetsAt: DateTime.tryParse(detail['resets_at']?.toString() ?? ''),
          ),
        );
      }
    } catch (_) {}
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
    );
  }

  @override
  void close() => _client.close();
}
