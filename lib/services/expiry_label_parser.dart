import '../models/pantry_item_model.dart';

class ExpiryLabelResult {
  final DateTime date;
  final String matchedText;
  final ExpiryConfidence confidence;
  final bool requiresConfirmation;

  const ExpiryLabelResult({
    required this.date,
    required this.matchedText,
    required this.confidence,
    required this.requiresConfirmation,
  });
}

class ExpiryLabelParser {
  const ExpiryLabelParser._();

  static ExpiryLabelResult? parse(String text, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final normalized = text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    final contextual = RegExp(
      r'(?:EXP(?:IRY|IRES)?|BEST\s*BEFORE|USE\s*BY|BB)\s*[:.\-]?\s*'
      r'(\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}|\d{4}[\/.\-]\d{1,2}[\/.\-]\d{1,2}|\d{1,2}\s+[A-Z]{3,9}\s+\d{2,4})',
    ).firstMatch(normalized);
    if (contextual != null) {
      final raw = contextual.group(1)!;
      final date = _parseDate(raw);
      if (date != null) {
        return ExpiryLabelResult(
          date: date,
          matchedText: contextual.group(0)!,
          confidence: ExpiryConfidence.high,
          requiresConfirmation: true,
        );
      }
    }

    final anyDate = RegExp(
      r'\b(\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}|\d{4}[\/.\-]\d{1,2}[\/.\-]\d{1,2})\b',
    ).allMatches(normalized);
    for (final match in anyDate) {
      final date = _parseDate(match.group(1)!);
      if (date != null &&
          date.isAfter(reference.subtract(const Duration(days: 730)))) {
        return ExpiryLabelResult(
          date: date,
          matchedText: match.group(0)!,
          confidence: ExpiryConfidence.low,
          requiresConfirmation: true,
        );
      }
    }
    return null;
  }

  static DateTime? _parseDate(String raw) {
    final clean = raw.trim().toUpperCase();
    final monthNames = <String, int>{
      'JAN': 1,
      'JANUARY': 1,
      'FEB': 2,
      'FEBRUARY': 2,
      'MAR': 3,
      'MARCH': 3,
      'APR': 4,
      'APRIL': 4,
      'MAY': 5,
      'JUN': 6,
      'JUNE': 6,
      'JUL': 7,
      'JULY': 7,
      'AUG': 8,
      'AUGUST': 8,
      'SEP': 9,
      'SEPT': 9,
      'SEPTEMBER': 9,
      'OCT': 10,
      'OCTOBER': 10,
      'NOV': 11,
      'NOVEMBER': 11,
      'DEC': 12,
      'DECEMBER': 12,
    };
    final named = RegExp(r'^(\d{1,2})\s+([A-Z]+)\s+(\d{2,4})$')
        .firstMatch(clean);
    if (named != null) {
      return _safeDate(
        _year(int.parse(named.group(3)!)),
        monthNames[named.group(2)!] ?? 0,
        int.parse(named.group(1)!),
      );
    }
    final parts = clean.split(RegExp(r'[\/.\-]')).map(int.parse).toList();
    if (parts.length != 3) return null;
    if (parts[0] > 999) return _safeDate(parts[0], parts[1], parts[2]);
    return _safeDate(_year(parts[2]), parts[1], parts[0]);
  }

  static int _year(int value) => value < 100 ? 2000 + value : value;

  static DateTime? _safeDate(int year, int month, int day) {
    if (year < 2000 ||
        year > 2200 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}
