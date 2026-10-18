class GroceryQueryNormalizer {
  GroceryQueryNormalizer._();

  static final Map<String, RegExp> _protectedForms = {
    'juice': RegExp(r'\bjuic(?:e|es)?\b', caseSensitive: false),
    'powder': RegExp(r'\bpowd(?:er|r)?\b', caseSensitive: false),
    'flour': RegExp(r'\bflou?r\b', caseSensitive: false),
    'oil': RegExp(r'\boil\b', caseSensitive: false),
    'vinegar': RegExp(r'\bvinegar\b', caseSensitive: false),
    'sauce': RegExp(r'\bsauce\b', caseSensitive: false),
    'jam': RegExp(r'\bjam\b', caseSensitive: false),
    'syrup': RegExp(r'\bsyrup\b', caseSensitive: false),
    'detergent': RegExp(r'\bdetergent\b', caseSensitive: false),
    'soap': RegExp(r'\bsoap\b', caseSensitive: false),
    'shampoo': RegExp(r'\bshampoo\b', caseSensitive: false),
    'formula': RegExp(r'\bformula\b', caseSensitive: false),
    'frozen': RegExp(r'\bfrozen\b', caseSensitive: false),
    'canned': RegExp(r'\bcanned?\b', caseSensitive: false),
    'dried': RegExp(r'\bdried\b', caseSensitive: false),
    'flavored': RegExp(r'\bflavou?red\b', caseSensitive: false),
    'baby': RegExp(r'\bbaby\b', caseSensitive: false),
    'diet': RegExp(r'\bdiet\b', caseSensitive: false),
    'zero': RegExp(r'\bzero\b', caseSensitive: false),
    'sugar-free': RegExp(r'\bsugar[ -]?free\b', caseSensitive: false),
    'lactose-free': RegExp(r'\blactose[ -]?free\b', caseSensitive: false),
    'gluten-free': RegExp(r'\bgluten[ -]?free\b', caseSensitive: false),
    'vegan': RegExp(r'\bvegan\b', caseSensitive: false),
    'halal': RegExp(r'\bhalal\b', caseSensitive: false),
  };

  static bool isSafeNormalization(String original, String normalized) {
    if (original.trim().isEmpty || normalized.trim().isEmpty) return false;
    for (final pattern in _protectedForms.values) {
      if (pattern.hasMatch(original) && !pattern.hasMatch(normalized)) {
        return false;
      }
    }
    return true;
  }

  static List<String> searchQueries(
    String wantedName,
    String normalizedName, {
    required double confidence,
  }) {
    final exact = wantedName.trim();
    final normalized = normalizedName.trim();
    if (exact.isEmpty) return const [];
    final canUseNormalized =
        confidence >= 0.7 &&
        normalized.isNotEmpty &&
        normalized.toLowerCase() != exact.toLowerCase() &&
        isSafeNormalization(exact, normalized);
    return canUseNormalized ? [normalized, exact] : [exact];
  }

  static bool isApprovedEquivalent(
    String normalizedName,
    String candidateName,
  ) {
    if (!isSafeNormalization(normalizedName, candidateName)) return false;
    final wantedTokens = _tokens(normalizedName);
    final candidateTokens = _tokens(candidateName);
    return wantedTokens.isNotEmpty &&
        wantedTokens.every(candidateTokens.contains);
  }

  static Set<String> _tokens(String value) =>
      RegExp(r'[a-z0-9]+')
          .allMatches(value.toLowerCase())
          .map((match) => match.group(0)!)
          .where((token) => token.length > 1)
          .map(
            (token) => token.endsWith('s') && token.length > 3
                ? token.substring(0, token.length - 1)
                : token,
          )
          .toSet();
}
