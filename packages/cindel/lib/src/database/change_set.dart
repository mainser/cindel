part of '../database.dart';

// Watcher change tracking.
//
// Local writes can report exact ids and sometimes document values immediately.
// External writes are detected through native collection revisions, so watchers
// may need to re-read snapshots when the exact changed ids are unknown.

/// A native-backed collection change observed by Cindel watchers.
///
/// Local writes include changed ids and, when Dart has the value available,
/// written documents. Changes from other database handles are reported as
/// external changes and require reading the native collection revision.
final class CindelChangeSet {
  const CindelChangeSet._({
    required this.collection,
    required this.documentIds,
    required this.documents,
    required this.hasUnknownDocuments,
    required this.isExternal,
    required this.revision,
  });

  /// Creates a change when another database handle advanced the collection.
  ///
  /// The affected ids are unknown, so watchers must treat it as potentially
  /// affecting any document in [collection].
  factory CindelChangeSet.external(String collection) {
    return CindelChangeSet._(
      collection: collection,
      documentIds: null,
      documents: const {},
      hasUnknownDocuments: true,
      isExternal: true,
      revision: null,
    );
  }

  /// Creates a change for one inserted or updated document.
  ///
  /// [document] is copied when provided. A missing [document] means the id is
  /// known but the value must be read from storage if a watcher needs it.
  factory CindelChangeSet.upsert(
    String collection,
    int id,
    CindelDocument? document,
  ) {
    return CindelChangeSet._(
      collection: collection,
      documentIds: {id},
      documents: document == null ? const {} : {id: Map.of(document)},
      hasUnknownDocuments: document == null,
      isExternal: false,
      revision: null,
    );
  }

  /// Creates a change for several inserted or updated documents.
  ///
  /// [ids] may include written documents whose values are not available to
  /// Dart. [documents] is copied to keep watcher metadata immutable.
  factory CindelChangeSet.upserts(
    String collection,
    Map<int, CindelDocument>? documents, {
    Iterable<int>? ids,
  }) {
    final documentCopies = {
      for (final entry in (documents ?? const <int, CindelDocument>{}).entries)
        entry.key: Map<String, Object?>.of(entry.value),
    };
    return CindelChangeSet._(
      collection: collection,
      documentIds: {...?ids, ...documentCopies.keys},
      documents: documentCopies,
      hasUnknownDocuments: documents == null,
      isExternal: false,
      revision: null,
    );
  }

  /// Creates a change for one deleted document.
  factory CindelChangeSet.delete(String collection, int id) {
    return CindelChangeSet.deletes(collection, [id]);
  }

  /// Creates a change for several deleted documents.
  factory CindelChangeSet.deletes(String collection, Iterable<int> ids) {
    return CindelChangeSet._(
      collection: collection,
      documentIds: ids.toSet(),
      documents: const {},
      hasUnknownDocuments: false,
      isExternal: false,
      revision: null,
    );
  }

  /// Creates a change set returned by the native post-commit change path.
  ///
  /// The native [revision] lets watchers avoid redundant reads when they have
  /// already observed the same collection revision.
  factory CindelChangeSet.native({
    required String collection,
    required int revision,
    required Iterable<int> ids,
    Map<int, CindelDocument> documents = const {},
    bool hasUnknownDocuments = false,
  }) {
    final documentCopies = {
      for (final entry in documents.entries)
        entry.key: Map<String, Object?>.of(entry.value),
    };
    return CindelChangeSet._(
      collection: collection,
      documentIds: ids.toSet(),
      documents: Map<int, CindelDocument>.unmodifiable(documentCopies),
      hasUnknownDocuments: hasUnknownDocuments,
      isExternal: false,
      revision: revision,
    );
  }

  /// Collection that changed.
  final String collection;

  /// Changed document ids, or `null` when the exact ids are unknown.
  final Set<int>? documentIds;

  /// Documents written by this handle, keyed by id when available.
  final Map<int, CindelDocument> documents;

  /// Whether this change includes local writes whose document value is not
  /// available to Dart.
  final bool hasUnknownDocuments;

  /// Whether this change was detected from another handle through revision
  /// polling instead of from local write metadata.
  final bool isExternal;

  /// Native collection revision after the commit, when delivered by the native
  /// change-set path.
  final int? revision;

  /// Returns whether this change can affect document [id].
  ///
  /// Returns `true` when [documentIds] is `null`, because the exact changed ids
  /// are unknown for external changes.
  bool mayAffectDocument(int id) {
    final ids = documentIds;
    return ids == null || ids.contains(id);
  }
}

// Merges local and native changes for a collection while a write transaction is
// active. Exact ids are preserved unless any merged change has unknown ids.
final class _CindelChangeSetBuilder {
  _CindelChangeSetBuilder(this.collection);

  final String collection;
  final Set<int> _documentIds = {};
  final Map<int, CindelDocument> _documents = {};
  bool _unknownIds = false;
  bool _hasUnknownDocuments = false;
  int? _revision;

  void add(CindelChangeSet change) {
    if (change.documentIds == null) {
      _unknownIds = true;
    } else {
      _documentIds.addAll(change.documentIds!);
    }
    _hasUnknownDocuments = _hasUnknownDocuments || change.hasUnknownDocuments;
    final revision = change.revision;
    if (revision != null) {
      final current = _revision;
      _revision = current == null || revision > current ? revision : current;
    }
    for (final entry in change.documents.entries) {
      _documents[entry.key] = Map<String, Object?>.of(entry.value);
    }
  }

  CindelChangeSet build() {
    return CindelChangeSet._(
      collection: collection,
      documentIds: _unknownIds ? null : Set<int>.of(_documentIds),
      documents: Map<int, CindelDocument>.unmodifiable(_documents),
      hasUnknownDocuments: _hasUnknownDocuments,
      isExternal: false,
      revision: _revision,
    );
  }
}

// Common watcher contract used by database-level document and collection
// watchers. It lets Cindel close active watchers without knowing their value
// type.
abstract interface class _RegisteredWatcher {
  Future<void> poll({bool force, CindelChangeSet? change});

  Future<void> close();
}

// Polling watcher with local-change short-circuiting.
//
// A watcher reads a snapshot when forced, when native revision changes, or when
// local metadata says the visible snapshot may have changed. Concurrent polls
// are coalesced so slow snapshot reads do not overlap.
final class _CindelWatcher<T> implements _RegisteredWatcher {
  _CindelWatcher({
    required Duration pollInterval,
    required bool fireImmediately,
    required bool Function() shouldPoll,
    required int Function() readRevision,
    required bool Function(CindelChangeSet change) shouldReadChange,
    required Future<T> Function(CindelChangeSet? change) readSnapshot,
    required bool Function(T left, T right)? areSnapshotsEqual,
    required void Function() onListen,
    required void Function() onCancel,
  }) : _pollInterval = pollInterval,
       _fireImmediately = fireImmediately,
       _shouldPoll = shouldPoll,
       _readRevision = readRevision,
       _shouldReadChange = shouldReadChange,
       _readSnapshot = readSnapshot,
       _areSnapshotsEqual = areSnapshotsEqual,
       _onListen = onListen,
       _onCancel = onCancel {
    _controller = StreamController<T>(
      onListen: () {
        _onListen();
        if (_fireImmediately) {
          unawaited(poll(force: true));
        } else {
          unawaited(_prime());
        }
        _timer = Timer.periodic(_pollInterval, (_) => unawaited(poll()));
      },
      onCancel: () {
        _timer?.cancel();
        _onCancel();
      },
    );
  }

  final Duration _pollInterval;
  final bool _fireImmediately;
  final bool Function() _shouldPoll;
  final int Function() _readRevision;
  final bool Function(CindelChangeSet change) _shouldReadChange;
  final Future<T> Function(CindelChangeSet? change) _readSnapshot;
  final bool Function(T left, T right)? _areSnapshotsEqual;
  final void Function() _onListen;
  final void Function() _onCancel;

  late final StreamController<T> _controller;
  Timer? _timer;
  int? _lastRevision;
  bool _hasLastSnapshot = false;
  T? _lastSnapshot;
  bool _isPolling = false;
  bool _needsPoll = false;
  bool _pendingForce = false;
  CindelChangeSet? _pendingChange;

  Stream<T> get stream => _controller.stream;

  Future<void> _prime() async {
    if (_isPolling || _controller.isClosed) {
      return;
    }
    _isPolling = true;
    try {
      _lastRevision = _readRevision();
      _lastSnapshot = await _readSnapshot(null);
      _hasLastSnapshot = true;
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
    }
  }

  Future<void> poll({bool force = false, CindelChangeSet? change}) async {
    if (_isPolling || _controller.isClosed) {
      if (!_controller.isClosed) {
        _needsPoll = true;
        _pendingForce = _pendingForce || force;
        _pendingChange ??= change;
      }
      return;
    }
    if (!force && !_shouldPoll()) {
      return;
    }
    _isPolling = true;
    try {
      final revision = change?.revision ?? _readRevision();
      if (!force && change != null && !_shouldReadChange(change)) {
        _lastRevision = revision;
        return;
      }
      if (!force && change == null && revision == _lastRevision) {
        return;
      }
      _lastRevision = revision;
      final snapshot = await _readSnapshot(change);
      final areSnapshotsEqual = _areSnapshotsEqual;
      if (!force && _hasLastSnapshot && areSnapshotsEqual != null) {
        final lastSnapshot = _lastSnapshot as T;
        if (areSnapshotsEqual(lastSnapshot, snapshot)) {
          _lastSnapshot = snapshot;
          return;
        }
      }
      _lastSnapshot = snapshot;
      _hasLastSnapshot = true;
      if (!_controller.isClosed) {
        _controller.add(snapshot);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _isPolling = false;
      if (_needsPoll && !_controller.isClosed) {
        final pendingForce = _pendingForce;
        final pendingChange = _pendingChange;
        _needsPoll = false;
        _pendingForce = false;
        _pendingChange = null;
        unawaited(poll(force: pendingForce, change: pendingChange));
      }
    }
  }

  Future<void> close() async {
    _timer?.cancel();
    await _controller.close();
  }
}
