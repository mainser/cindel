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
lowercased so they match the default case-insensitive word index behavior.

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
