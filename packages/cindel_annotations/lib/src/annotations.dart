/// Marks a Dart class as a Cindel collection.
class Collection {
  /// Creates a collection annotation.
  ///
  /// When [name] is omitted, the generator uses the class name with a lower
  /// camel-case first letter.
  const Collection({this.name});

  /// The storage collection name.
  final String? name;
}

/// Marks a Dart class as a Cindel collection.
const collection = Collection();

/// Marks a field as indexed.
class Index {
  /// Creates an index annotation.
  const Index({
    this.unique = false,
    this.caseSensitive = true,
    this.type = CindelIndexType.value,
  });

  /// Whether the index requires unique values.
  final bool unique;

  /// Whether string values keep case-sensitive lookup semantics.
  ///
  /// This option only applies to `String` fields.
  final bool caseSensitive;

  /// Storage strategy used for this index.
  final CindelIndexType type;
}

/// Marks a field as indexed.
const index = Index();

/// Storage strategy for a Cindel index.
enum CindelIndexType {
  /// Stores the original sortable value.
  ///
  /// Value indexes support equality and range-style helpers.
  value,

  /// Stores a compact stable hash of the indexed value.
  ///
  /// Hash indexes support equality helpers only.
  hash,

  /// Splits a string field into searchable word tokens.
  ///
  /// Word indexes support exact token lookup and token-prefix lookup.
  words,
}
