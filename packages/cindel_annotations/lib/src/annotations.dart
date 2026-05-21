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

/// Excludes a field from generated Cindel persistence.
class Ignore {
  /// Creates an ignore annotation.
  const Ignore();
}

/// Excludes a field from generated Cindel persistence.
const ignore = Ignore();

/// Configures how enum fields are persisted.
class Enumerated {
  /// Creates an enum persistence annotation.
  const Enumerated(this.type, {this.valueField});

  /// Persistence strategy used for the enum value.
  final CindelEnumType type;

  /// Enum instance field used when [type] is [CindelEnumType.value].
  final String? valueField;
}

/// Enum persistence strategy.
enum CindelEnumType {
  /// Stores the enum case name.
  name,

  /// Stores the enum case index.
  ordinal,

  /// Stores the value of an enum instance field.
  value,
}

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
