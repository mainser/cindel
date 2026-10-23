import 'dart:async';

Future<void> settleWatchMicrotasks() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

final class WatchTestClock {
  Duration now = Duration.zero;
  final List<_Timer> _timers = [];
  int peakTimers = 0;
  int get activeTimers => _timers.where((timer) => timer.isActive).length;

  Timer timer(Duration delay, void Function() callback) {
    final timer = _Timer(now + delay, callback);
    _timers.removeWhere((timer) => !timer.isActive);
    _timers.add(timer);
    if (activeTimers > peakTimers) peakTimers = activeTimers;
    return timer;
  }

  Future<void> advance(Duration duration) async {
    final end = now + duration;
    while (true) {
      final due =
          _timers.where((timer) => timer.isActive && timer.at <= end).toList()
            ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final timer = due.first;
      now = timer.at;
      timer.fire();
      await settleWatchMicrotasks();
    }
    now = end;
    await settleWatchMicrotasks();
  }
}

final class _Timer implements Timer {
  _Timer(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    _active = false;
    _tick++;
    callback();
  }
}
