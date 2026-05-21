/// Splits [text] into word tokens suitable for Cindel word indexes.
///
/// Punctuation and whitespace are treated as separators. Repeated tokens are
/// returned once, preserving their first-seen order. Tokens are lower-cased by
/// default so they match the default case-insensitive word-index behavior.
List<String> cindelSplitWords(String text, {bool caseSensitive = false}) {
  final tokens = <String>[];
  final seen = <String>{};
  for (final match in _wordPattern.allMatches(text)) {
    final rawToken = match.group(0);
    if (rawToken == null || rawToken.isEmpty) {
      continue;
    }
    final token = caseSensitive ? rawToken : rawToken.toLowerCase();
    if (seen.add(token)) {
      tokens.add(token);
    }
  }
  return tokens;
}

final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);
