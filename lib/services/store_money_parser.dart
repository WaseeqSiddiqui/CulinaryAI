double? parseStoreMoney(String? raw) {
  if (raw == null) return null;
  final match = RegExp(
    r'^(?:(?:Rs\.?|PKR|₨)\s*)?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$',
    caseSensitive: false,
  ).firstMatch(raw.replaceAll('\u00a0', ' ').trim());
  if (match == null) return null;
  final amount = double.tryParse(
    '${match.group(1)!.replaceAll(',', '')}.${match.group(2) ?? '0'}',
  );
  return amount != null && amount.isFinite ? amount : null;
}
