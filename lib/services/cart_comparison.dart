import '../models/store_models.dart';

CartComparison compareCart(
  List<AutomationItemResult> intended,
  List<CartLine> actual,
) {
  final unmatched = List<CartLine>.of(actual);
  final matched = <CartLine>[];
  final missing = <String>[];
  for (final item in intended.where((item) => item.status == AddStatus.added)) {
    final wanted = (item.productName ?? item.wantedName).toLowerCase();
    final index = unmatched.indexWhere((line) {
      final actualName = line.name.toLowerCase();
      return actualName.contains(wanted) || wanted.contains(actualName);
    });
    if (index < 0) {
      missing.add(item.wantedName);
    } else {
      matched.add(unmatched.removeAt(index));
    }
  }
  return CartComparison(matched: matched, missing: missing);
}
