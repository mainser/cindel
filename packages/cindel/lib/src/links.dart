import 'dart:collection';

import 'database.dart' if (dart.library.js_interop) 'web/database.dart';
import 'schema.dart';

/// A generated to-one Cindel relation.
final class CindelLink<T> {
  /// Creates an unloaded to-one link.
  CindelLink();

  _CindelLinkBinding<T>? _binding;
  T? _value;

  /// The linked object currently held in memory.
  T? get value => _value;

  set value(T? value) {
    _value = value;
  }

  /// Loads the linked object from storage.
  Future<void> load() async {
    final binding = _requireBinding();
    final values = await binding.load();
    _value = values.isEmpty ? null : values.first;
  }

  /// Persists the current linked object.
  Future<void> save() {
    final binding = _requireBinding();
    return binding.save(_value == null ? <T>[] : <T>[_value as T]);
  }

  /// Clears in-memory state without deleting persisted relations.
  Future<void> reset() async {
    _value = null;
  }

  /// Binds this generated link to its owner object.
  ///
  /// Generated schema code calls this when an object is stored or hydrated.
  /// Application code normally uses [load], [save], and [reset] instead.
  void bind(
    CindelDatabase database,
    CindelCollectionSchema<Object?> ownerSchema,
    Object owner,
    CindelLinkSchema link,
  ) {
    _binding = _CindelLinkBinding<T>(database, ownerSchema, owner, link);
  }

  _CindelLinkBinding<T> _requireBinding() {
    final binding = _binding;
    if (binding == null) {
      throw StateError('CindelLink is not bound to a database object.');
    }
    return binding;
  }
}

/// A generated to-many Cindel relation.
final class CindelLinks<T> extends IterableBase<T> {
  /// Creates an unloaded to-many link set.
  CindelLinks();

  _CindelLinkBinding<T>? _binding;
  final List<T> _values = <T>[];

  @override
  Iterator<T> get iterator => _values.iterator;

  /// Adds [object] if it is not already present.
  bool add(T object) {
    if (_values.any((value) => identical(value, object))) {
      return false;
    }
    _values.add(object);
    return true;
  }

  /// Removes [object] from the in-memory set.
  bool remove(T object) {
    return _values.remove(object);
  }

  /// Loads linked objects from storage.
  Future<void> load() async {
    final binding = _requireBinding();
    _values
      ..clear()
      ..addAll(await binding.load());
  }

  /// Persists the current linked objects.
  Future<void> save() {
    final binding = _requireBinding();
    return binding.save(_values);
  }

  /// Clears in-memory state without deleting persisted relations.
  Future<void> reset() async {
    _values.clear();
  }

  /// Binds this generated link set to its owner object.
  ///
  /// Generated schema code calls this when an object is stored or hydrated.
  /// Application code normally uses [load], [save], [reset], [add], and
  /// [remove] instead.
  void bind(
    CindelDatabase database,
    CindelCollectionSchema<Object?> ownerSchema,
    Object owner,
    CindelLinkSchema link,
  ) {
    _binding = _CindelLinkBinding<T>(database, ownerSchema, owner, link);
  }

  _CindelLinkBinding<T> _requireBinding() {
    final binding = _binding;
    if (binding == null) {
      throw StateError('CindelLinks is not bound to a database object.');
    }
    return binding;
  }
}

final class _CindelLinkBinding<T> {
  _CindelLinkBinding(this.database, this.ownerSchema, this.owner, this.link);

  final CindelDatabase database;
  final CindelCollectionSchema<Object?> ownerSchema;
  final Object owner;
  final CindelLinkSchema link;

  Future<List<T>> load() {
    final ownerId = database.cindelObjectId(ownerSchema.name, owner);
    if (link.isBacklink) {
      return database.loadBacklinkObjects<T>(
        ownerCollection: ownerSchema.name,
        ownerId: ownerId,
        sourceCollection: link.targetCollection,
        sourceLinkName: link.backlinkTo!,
      );
    }
    return database.loadLinkedObjects<T>(
      sourceCollection: ownerSchema.name,
      sourceId: ownerId,
      linkName: link.name,
      targetCollection: link.targetCollection,
    );
  }

  Future<void> save(List<T> values) async {
    if (link.isBacklink) {
      throw StateError('Backlinks are read-only.');
    }
    final ownerId = database.cindelObjectId(ownerSchema.name, owner);
    final ids = <int>{};
    for (final value in values) {
      ids.add(database.cindelObjectId(link.targetCollection, value as Object));
    }
    await database.saveLinkIds(
      sourceCollection: ownerSchema.name,
      sourceId: ownerId,
      linkName: link.name,
      targetCollection: link.targetCollection,
      targetIds: ids,
    );
  }
}
