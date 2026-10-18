double? parseStoreMoney(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'\d+(?:,\d{3})*(?:\.\d{1,2})?').firstMatch(raw);
  if (match == null) return null;
  return double.tryParse(match.group(0)!.replaceAll(',', ''));
}
