import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigService {
  static const String _prefKey = 'culinary_api_base_url';

  /// Default production cloud backend (Render)
  static const String defaultProductionUrl = 'https://culinary-ai-backend.onrender.com';

  static const String defaultLocalIp = '192.168.100.147';
  static const String defaultPort = '8000';

  static const List<String> presetUrls = [
    defaultProductionUrl,
    'http://192.168.100.147:8000',
    'http://127.0.0.1:8000',
    'http://10.0.2.2:8000',
  ];

  static String _cachedUrl = '';

  static String get fallbackDefaultUrl {
    const envUrl = String.fromEnvironment('CULINARY_API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    return defaultProductionUrl;
  }

  static String get currentBaseUrl {
    if (_cachedUrl.isNotEmpty) return _cachedUrl;
    return fallbackDefaultUrl;
  }

  static Future<String> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey)?.trim();
      // If no URL saved, or if it was an old local Wi-Fi IP, migrate to cloud production URL
      if (saved != null &&
          saved.isNotEmpty &&
          !saved.contains('192.168.') &&
          !saved.contains('10.0.2.2') &&
          !saved.contains('127.0.0.1')) {
        _cachedUrl = saved;
        return _cachedUrl;
      }
    } catch (_) {}
    _cachedUrl = fallbackDefaultUrl;
    return _cachedUrl;
  }


  static Future<void> setBaseUrl(String url) async {
    final clean = url.trim().replaceFirst(RegExp(r'/+$'), '');
    _cachedUrl = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, clean);
    } catch (_) {}
  }

  static Future<({bool success, String message, int? latencyMs})> testConnection([
    String? testUrl,
  ]) async {
    final target = (testUrl ?? currentBaseUrl).trim().replaceFirst(RegExp(r'/+$'), '');
    if (target.isEmpty) {
      return (success: false, message: 'Server URL cannot be empty.', latencyMs: null);
    }

    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('$target/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (
          success: true,
          message: 'Connected successfully (HTTP ${response.statusCode})',
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      } else {
        return (
          success: false,
          message: 'Server responded with error ${response.statusCode}',
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
    } on TimeoutException {
      return (
        success: false,
        message: 'Connection timed out. Check Wi-Fi and port 8000.',
        latencyMs: null,
      );
    } catch (e) {
      return (
        success: false,
        message: 'Could not connect: ${e.toString().split('\n').first}',
        latencyMs: null,
      );
    }
  }
}
