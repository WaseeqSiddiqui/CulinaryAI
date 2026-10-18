import 'dart:convert';

import 'package:flutter/services.dart';

class StoreSelectorConfig {
  const StoreSelectorConfig(this.values);
  final Map<String, String> values;

  String get homeUrl => values['home_url'] ?? '';
  String value(String key) => values[key] ?? '';

  List<String> list(String key) =>
      value(key)
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);

  bool hasAll(Iterable<String> keys) =>
      keys.every((key) => value(key).trim().isNotEmpty);

  static Future<StoreSelectorConfig> load(String store) async {
    final source = await rootBundle.loadString('assets/store_selectors.json');
    final root = jsonDecode(source) as Map<String, dynamic>;
    final raw = Map<String, dynamic>.from(root[store] as Map);
    return StoreSelectorConfig(
      raw.map((key, value) => MapEntry(key, value.toString())),
    );
  }
}
