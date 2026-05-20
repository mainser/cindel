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
  const Index({this.unique = false});

  /// Whether the index requires unique values.
  final bool unique;
}

/// Marks a field as indexed.
const index = Index();
