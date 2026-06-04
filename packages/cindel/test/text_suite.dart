import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel text helpers', () {
    // Scenario: User text contains punctuation, accents, repeated words, and
    // numbers.
    // Covers:
    // - [Cindel.splitWords] Unicode token discovery.
    // - Default lower-case normalization.
    // - Duplicate token removal while preserving first-seen order.
    // Expected: Tokens are suitable for case-insensitive word indexes.
    test('splits unicode text into normalized unique words.', () {
      // Arrange.
      const text = 'Café-rápido, café! Alpha ALPHA 42.';

      // Act.
      final tokens = Cindel.splitWords(text);

      // Assert.
      expect(tokens, ['café', 'rápido', 'alpha', '42']);
    });

    // Scenario: A case-sensitive index wants original token casing.
    // Covers:
    // - [Cindel.splitWords] caseSensitive option.
    // Expected: Tokens preserve their source casing when requested.
    test('can preserve token casing.', () {
      // Arrange.
      const text = 'Alpha alpha ALPHA';

      // Act.
      final tokens = Cindel.splitWords(text, caseSensitive: true);

      // Assert.
      expect(tokens, ['Alpha', 'alpha', 'ALPHA']);
    });
  });
}
