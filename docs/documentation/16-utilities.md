# Utilities

Cindel exposes a small set of public utility helpers. Most application code
will use generated collections and queries, but utilities are useful when an
app needs to match Cindel behavior outside a database operation.

## `Cindel.splitWords`

`Cindel.splitWords` splits text the same way Cindel word indexes do.

```dart
final tokens = Cindel.splitWords(
  'Ship the docs!',
  caseSensitive: false,
);
```

The result can be used to preview or test tokenization:

```dart
for (final token in tokens) {
  print(token);
}
```

For the example above, the result is:

```dart
['ship', 'the', 'docs']
```

Punctuation and whitespace act as separators. Repeated words are returned only
once, keeping the order in which they first appeared. By default, tokens are
lowercased. `@Index` itself defaults to `caseSensitive: true`, including word
indexes. Set `caseSensitive: false` explicitly on the index when using the
utility's lowercase default, or pass `true` to the utility to match a
case-sensitive index.

Use this helper when working with `CindelIndexType.words`:

```dart
@Collection(name: 'products')
class Product {
  Id dbId = autoIncrement;

  @Index(type: CindelIndexType.words, caseSensitive: false)
  late String searchText;
}
```

For example, an app can show which words a search field will match:

```dart
final queryWords = Cindel.splitWords(
  searchInput,
  caseSensitive: false,
);
```

Use the same `caseSensitive` value that the word index uses.

Tokens consist of letters and numbers; punctuation separates them. This helper
does not stem words or expand synonyms. The generated `WordsContain` and
`WordsStartWith` helpers use the first token from their argument, so pass one
word or prefix at a time rather than treating them as phrase-search methods.

## Practical Guidance

Use `Cindel.splitWords` for diagnostics, tests, search previews, and tooling
around word indexes.

Do not use it as a replacement for generated word-index query helpers. Query
the database through generated `where()` helpers when you want to find matching
objects:

```dart
final products = await db.products
    .where()
    .searchTextWordsContain('laptop')
    .findAll();
```
