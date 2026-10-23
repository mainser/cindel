/// Builds an unambiguous key for a tuple of internal document values.
///
/// Containers retain their structure, and scalar types and text are prefixed
/// with their lengths. Data can therefore contain any delimiter without
/// changing field, element, or object boundaries. Sets compare the full key,
/// so hash collisions cannot discard a different tuple.
String cindelDistinctKey(
  Map<String, Object?> document,
  Iterable<String> fields,
) {
  final buffer = StringBuffer();
  for (final field in fields) {
    _writeValue(buffer, document[field]);
  }
  return buffer.toString();
}

void _writeValue(StringBuffer buffer, Object? value) {
  if (value == null) {
    buffer.write('n');
  } else if (value is List) {
    buffer.write('l${value.length}:');
    for (final element in value) {
      _writeValue(buffer, element);
    }
  } else if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    buffer.write('o${keys.length}:');
    for (final key in keys) {
      _writeText(buffer, key);
      _writeValue(buffer, value[key]);
    }
  } else {
    // Preserve scalar type/value distinctions without using a container's
    // runtime implementation type or ambiguous toString representation.
    buffer.write('v');
    _writeText(buffer, value.runtimeType.toString());
    _writeText(buffer, value.toString());
  }
}

void _writeText(StringBuffer buffer, String text) {
  buffer
    ..write(text.length)
    ..write(':')
    ..write(text);
}
