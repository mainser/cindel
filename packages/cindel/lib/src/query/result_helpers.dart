part of '../query.dart';

// Shared helpers for query validation and Dart-side result processing.
//
// These functions are used when native storage cannot fully execute a query, and
// they keep the Dart fallback semantics aligned with generated query helpers.

// Compares immutable query modifier lists when validating `anyOf` and `allOf`.
bool _sortKeyListsEqual(List<_CindelSortKey> left, List<_CindelSortKey> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    final leftKey = left[i];
    final rightKey = right[i];
    if (leftKey.field != rightKey.field || leftKey.order != rightKey.order) {
      return false;
    }
  }
  return true;
}

// String-list equality without allocating intermediate tuples.
bool _stringListsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

// Looks up a schema field and reports the generated Dart type in the error.
CindelFieldSchema _schemaField<T>(
  CindelCollectionSchema<T> schema,
  String field,
) {
  for (final schemaField in schema.fields) {
    if (schemaField.name == field) {
      return schemaField;
    }
  }
  throw CindelSchemaError(
    'Field `$field` is not part of `${schema.dartName}`.',
  );
}

// Shared guard for generated word-index query helpers.
void _checkWordsIndex(CindelFieldSchema field) {
  if (field.indexType != CindelIndexType.words) {
    throw CindelQueryError('Field `${field.name}` is not a word index.');
  }
}

// Field names must be non-empty because they become document keys, native
// projection targets, and sort/distinct fields.
void _checkFieldName(String field) {
  if (field.trim().isEmpty) {
    throw ArgumentError.value(field, 'field', 'Must not be empty.');
  }
}

// One requested sort key. Sorting is stable because `_sortDocuments` retains the
// original document position as a final tie-breaker.
final class _CindelSortKey {
  const _CindelSortKey(this.field, this.order);

  final String field;
  final CindelSortOrder order;
}

// Document plus original position, used for stable Dart-side sorting.
final class _PositionedDocument {
  const _PositionedDocument(this.document, this.position);

  final CindelDocument document;
  final int position;
}

// Applies Dart-side sort keys in order and preserves original order for ties.
List<CindelDocument> _sortDocuments(
  List<CindelDocument> documents,
  List<_CindelSortKey> sortKeys,
) {
  final positioned = [
    for (var index = 0; index < documents.length; index += 1)
      _PositionedDocument(documents[index], index),
  ];
  positioned.sort((left, right) {
    for (final sortKey in sortKeys) {
      final comparison = _compareValues(
        left.document[sortKey.field],
        right.document[sortKey.field],
      );
      if (comparison == 0) {
        continue;
      }
      return sortKey.order == CindelSortOrder.ascending
          ? comparison
          : -comparison;
    }
    return left.position.compareTo(right.position);
  });
  return [for (final item in positioned) item.document];
}

// Compares Cindel document values using the same broad ordering used by Dart
// fallback query sorting.
int _compareValues(Object? left, Object? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return -1;
  }
  if (right == null) {
    return 1;
  }
  if (left is num && right is num) {
    return left.compareTo(right);
  }
  if (left is String && right is String) {
    return left.compareTo(right);
  }
  if (left is bool && right is bool) {
    return left == right ? 0 : (left ? 1 : -1);
  }
  return left.toString().compareTo(right.toString());
}

// Keeps the first document for each distinct field tuple.
List<CindelDocument> _distinctDocuments(
  List<CindelDocument> documents,
  List<String> fields,
) {
  final seen = <String>{};
  final distinct = <CindelDocument>[];
  for (final document in documents) {
    final key = _distinctKey(document, fields);
    if (seen.add(key)) {
      distinct.add(document);
    }
  }
  return distinct;
}

// Builds a simple stable key for Dart-side distinct processing.
String _distinctKey(CindelDocument document, List<String> fields) {
  return fields
      .map((field) => '${document[field].runtimeType}:${document[field]}')
      .join('\u0001');
}

// Applies offset and limit after filtering, sorting, and distinct.
List<CindelDocument> _windowDocuments(
  List<CindelDocument> documents,
  int offset,
  int? limit,
) {
  if (offset >= documents.length) {
    return <CindelDocument>[];
  }
  final end = limit == null
      ? documents.length
      : (offset + limit).clamp(0, documents.length);
  return documents.sublist(offset, end);
}

// Computes an inclusive upper bound for prefix range scans.
String _inclusivePrefixUpperBound(String prefix) {
  if (prefix.isEmpty) {
    return prefix;
  }
  final lastCodeUnit = prefix.codeUnitAt(prefix.length - 1);
  final nextCodeUnit = lastCodeUnit + 1;
  return '${prefix.substring(0, prefix.length - 1)}'
      '${String.fromCharCode(nextCodeUnit)}';
}
