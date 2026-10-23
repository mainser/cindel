import 'dart:async';

/// Internal scheduler shared by native and Web database handles.
///
/// A handle owns one timer. Due subscriptions share one revision read per
/// collection, including initialization; snapshots remain subscription-local.
final class CindelWatchCoordinator<C> {
  CindelWatchCoordinator({
    required this.readRevision,
    required this.shouldPoll,
    required this.revisionOf,
    required this.mergeChanges,
    Duration Function()? now,
    Timer Function(Duration, void Function())? createTimer,
  }) : _now = now ?? (Stopwatch()..start()).elapsedDuration,
       _createTimer = createTimer ?? Timer.new;

  final FutureOr<int> Function(String collection) readRevision;
  final bool Function() shouldPoll;
  final int? Function(C change) revisionOf;
  final C Function(C left, C right) mergeChanges;
  final Duration Function() _now;
  final Timer Function(Duration, void Function()) _createTimer;
  final Map<String, _Collection<C>> _collections = {};
  Timer? _timer;
  bool _stopped = false;
  Future<void>? _closeFuture;

  bool get isEmpty =>
      _collections.values.every((group) => group.observers.isEmpty);
  bool hasWatchers(String collection) =>
      _collections[collection]?.observers.isNotEmpty ?? false;

  Stream<T> watch<T>(
    String collection, {
    required Duration pollInterval,
    required bool fireImmediately,
    required bool Function(C change) shouldReadChange,
    required Future<T> Function(C? change) readSnapshot,
    required bool Function(T left, T right)? areSnapshotsEqual,
  }) {
    final observer = _Watcher<T, C>(
      this,
      collection,
      pollInterval,
      fireImmediately,
      shouldReadChange,
      readSnapshot,
      areSnapshotsEqual,
    );
    return observer.controller.stream;
  }

  void _attach(_Observer<C> observer) {
    if (_stopped) {
      unawaited(observer.close());
      return;
    }
    final group = _collections.putIfAbsent(
      observer.collection,
      () => _Collection<C>(observer.collection, _now()),
    );
    observer.due = _now();
    group.observers.add(observer);
    _schedule();
  }

  void _detach(_Observer<C> observer) {
    final group = _collections[observer.collection];
    if (group == null) return;
    group.observers.remove(observer);
    group.waiting.remove(observer);
    if (group.observers.isEmpty) {
      group.pendingChange = null;
      if (!group.reading) _collections.remove(observer.collection);
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_stopped || isEmpty) return;
    Duration? next;
    for (final group in _collections.values) {
      for (final observer in group.observers) {
        if (next == null || observer.due < next) next = observer.due;
      }
    }
    if (next == null) return;
    final delay = next - _now();
    // Timer implementations truncate sub-millisecond durations. Round up to
    // avoid repeatedly scheduling zero-delay ticks before a deadline is due.
    _timer = _createTimer(
      delay <= Duration.zero
          ? Duration.zero
          : Duration(milliseconds: (delay.inMicroseconds + 999) ~/ 1000),
      _tick,
    );
  }

  void _tick() {
    _timer = null;
    if (_stopped) return;
    final now = _now();
    for (final group in _collections.values.toList()) {
      for (final observer in group.observers) {
        if (observer.due <= now) {
          // Advance from now, without queuing catch-up reads after a slow tick.
          final elapsed = (now - group.origin).inMicroseconds;
          final period = observer.interval.inMicroseconds;
          observer.due =
              group.origin +
              Duration(microseconds: (elapsed ~/ period + 1) * period);
          if (shouldPoll()) group.waiting.add(observer);
        }
      }
      if (group.waiting.isNotEmpty) unawaited(_read(group));
    }
    _schedule();
  }

  bool _active(_Collection<C> group) =>
      !_stopped && identical(_collections[group.name], group);

  Future<void> _read(_Collection<C> group) async {
    if (group.reading || !_active(group) || !shouldPoll()) return;
    group.reading = true;
    final generation = group.generation;
    try {
      final revision = await readRevision(group.name);
      if (!_active(group) || !shouldPoll()) return;
      // A local commit may have delivered a newer revision while Web awaited
      // its response. That stale response must not roll subscriptions back.
      if (generation != group.generation) return;
      final observers = group.waiting.toList();
      final change = group.pendingChange;
      group.waiting.clear();
      group.pendingChange = null;
      for (final observer in observers) {
        observer.offer(revision, change);
      }
    } catch (error, stack) {
      if (_active(group) && generation == group.generation) {
        final observers = group.waiting.toList();
        group.waiting.clear();
        for (final observer in observers) {
          observer.addError(error, stack);
        }
      }
    } finally {
      group.reading = false;
      if (_active(group) && group.observers.isEmpty) {
        _collections.remove(group.name);
      }
      // Only a superseding local change requests an immediate replacement.
      // Ordinary failures retry on the next deadline, never in a busy loop.
      if (_active(group) &&
          generation != group.generation &&
          group.waiting.isNotEmpty &&
          shouldPoll()) {
        unawaited(_read(group));
      }
    }
  }

  void notify(String collection, C change) {
    final group = _collections[collection];
    if (group == null || _stopped) return;
    group.generation++;
    final pending = group.pendingChange;
    final merged = pending == null ? change : mergeChanges(pending, change);
    final revision = revisionOf(change);
    if (revision == null) {
      group.pendingChange = merged;
      group.waiting.addAll(group.observers);
      unawaited(_read(group));
    } else {
      group.pendingChange = null;
      group.waiting.clear();
      for (final observer in group.observers.toList()) {
        observer.offer(revision, merged);
      }
    }
  }

  /// Stops work immediately, before database teardown awaits native/Worker IO.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    for (final group in _collections.values) {
      group.waiting.clear();
      group.pendingChange = null;
      for (final observer in group.observers) {
        observer.stop();
      }
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    stop();
    final observers = [
      for (final group in _collections.values) ...group.observers,
    ];
    _collections.clear();
    // Preserve StreamController's paused-subscription completion contract.
    // Snapshot callbacks are not awaited: they may themselves call close().
    await Future.wait([for (final observer in observers) observer.close()]);
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}

final class _Collection<C> {
  _Collection(this.name, this.origin);
  final String name;
  final Duration origin;
  final Set<_Observer<C>> observers = {};
  final Set<_Observer<C>> waiting = {};
  bool reading = false;
  int generation = 0;
  C? pendingChange;
}

abstract class _Observer<C> {
  _Observer(this.collection, this.interval);
  final String collection;
  final Duration interval;
  Duration due = Duration.zero;
  void offer(int revision, C? change);
  void addError(Object error, StackTrace stack);
  void stop();
  Future<void> close();
}

final class _Sample<C> {
  _Sample(this.revision, this.change);
  final int revision;
  final C? change;
}

final class _Watcher<T, C> extends _Observer<C> {
  _Watcher(
    this.owner,
    super.collection,
    super.interval,
    this.fireImmediately,
    this.shouldReadChange,
    this.readSnapshot,
    this.areSnapshotsEqual,
  ) {
    controller = StreamController<T>(
      onListen: () => owner._attach(this),
      onCancel: () {
        stop();
        owner._detach(this);
      },
    );
  }

  final CindelWatchCoordinator<C> owner;
  final bool fireImmediately;
  final bool Function(C) shouldReadChange;
  final Future<T> Function(C?) readSnapshot;
  final bool Function(T, T)? areSnapshotsEqual;
  late final StreamController<T> controller;
  bool _stopped = false;
  bool _reading = false;
  bool _initialized = false;
  bool _needsSnapshot = false;
  int? _revision;
  T? _snapshot;
  _Sample<C>? _pending;

  @override
  void offer(int revision, C? change) {
    if (_stopped) return;
    final previous = _pending;
    // Unknown/external changes dominate exact local metadata. Otherwise merge
    // all pending changes, rather than retaining only the first changed ID.
    _pending = _Sample(
      revision,
      previous == null
          ? change
          : previous.change == null || change == null
          ? null
          : owner.mergeChanges(previous.change as C, change),
    );
    if (!_reading) unawaited(_drain());
  }

  Future<void> _drain() async {
    _reading = true;
    try {
      while (!_stopped && _pending != null) {
        if (!owner.shouldPoll()) return;
        final sample = _pending!;
        _pending = null;
        final initial = !_initialized;
        try {
          if (!initial && !_needsSnapshot) {
            final change = sample.change;
            if (change != null && !shouldReadChange(change)) {
              _revision = sample.revision;
              continue;
            }
            if (change == null && sample.revision == _revision) continue;
          }
          final snapshot = await readSnapshot(
            initial || _needsSnapshot ? null : sample.change,
          );
          if (_stopped) return;
          if (!owner.shouldPoll()) {
            _pending = _Sample(_pending?.revision ?? sample.revision, null);
            return;
          }
          final equal =
              !initial &&
              areSnapshotsEqual != null &&
              areSnapshotsEqual!(_snapshot as T, snapshot);
          _snapshot = snapshot;
          // Failed snapshots never acknowledge a revision; the next poll can
          // retry it even when no additional write has happened.
          _revision = sample.revision;
          _initialized = true;
          _needsSnapshot = false;
          if ((!initial || fireImmediately) && !equal) controller.add(snapshot);
        } catch (error, stack) {
          _needsSnapshot = true;
          addError(error, stack);
          final pending = _pending;
          if (pending != null) _pending = _Sample(pending.revision, null);
        }
      }
    } finally {
      _reading = false;
    }
  }

  @override
  void addError(Object error, StackTrace stack) {
    if (!_stopped) controller.addError(error, stack);
  }

  @override
  void stop() {
    _stopped = true;
    _pending = null;
    _snapshot = null;
  }

  @override
  Future<void> close() {
    stop();
    return controller.close();
  }
}
