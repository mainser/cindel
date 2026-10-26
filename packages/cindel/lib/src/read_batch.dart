import 'dart:collection';

import 'schema.dart';

// Internal ownership boundary: only this immutable wrapper can carry an
// already captured ID list between the collection and database layers.
List<int> captureReadIds(Iterable<int> ids) =>
    ids is _ReadIds ? ids : _ReadIds(ids.toList(growable: false));

// Direct database callers still receive a private snapshot. Never reuse an
// arbitrary caller-owned List, including an unmodifiable view of one.
List<int> materializeReadIds(Iterable<int> ids) =>
    ids is _ReadIds ? ids._values : ids.toList(growable: false);

final class _ReadIds extends ListBase<int> {
  _ReadIds(this._values);

  final List<int> _values;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('Read IDs are immutable.');

  @override
  int operator [](int index) => _values[index];

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read IDs are immutable.');
}

// Called only after hydration, error checking and reader release. Binding
// mutates the objects, not the list; collections can return the owned result.
List<T?> completeReadBatch<T>(
  List<T?> objects,
  Object database,
  CindelCollectionSchema<T> schema,
) {
  final bindLinks = schema.bindLinks;
  if (bindLinks != null) {
    for (final object in objects) {
      if (object != null) {
        bindLinks(database, schema, object);
      }
    }
  }
  return objects;
}
