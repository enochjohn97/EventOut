import 'package:flutter/foundation.dart';

/// Lightweight load-time instrumentation so the under-2s target is checked
/// against real measurements instead of assumptions.
///
/// Checkpoints print as `[timing] <name>=<n>ms`. Flows measured against the
/// under-2s target print as `[timing] <name>=<n>ms (budget 2000ms: PASS)`,
/// so a single run shows where each budgeted flow lands. Cold-start
/// checkpoints (first frame, endpoint/config ready) are reported without a
/// verdict. Disable with `--dart-define=LOAD_TIMINGS=false`.
class LoadTimings {
  LoadTimings._();

  static const bool enabled = bool.fromEnvironment(
    'LOAD_TIMINGS',
    defaultValue: true,
  );

  /// Target for every load measured here, including the payment flow.
  static const int budgetMs = 2000;

  /// Clock started by [launch] at the very first line of `main()`.
  static final Stopwatch _sinceLaunch = Stopwatch()..start();

  /// Milestones already recorded, so repeated paints do not re-log.
  static final Set<String> _once = {};

  /// Starts the launch clock. Call as the first statement of `main()`.
  static void launch() {
    if (!_sinceLaunch.isRunning) _sinceLaunch.start();
  }

  static int get sinceLaunchMs => _sinceLaunch.elapsedMilliseconds;

  /// Records a milestone measured from launch. Checkpoints pass
  /// `budgeted: false` (the default); set it only for flows that carry the
  /// under-2s target, e.g. the first feed paint.
  static void mark(String name, {bool budgeted = false}) {
    if (!enabled) return;
    _report(name, sinceLaunchMs, budgeted: budgeted);
  }

  /// Like [mark], but only the first occurrence is recorded.
  static void markOnce(String name, {bool budgeted = false}) {
    if (!enabled || !_once.add(name)) return;
    mark(name, budgeted: budgeted);
  }

  static Stopwatch start() => Stopwatch()..start();

  /// Ends [timer] and reports its duration under [name]. Durations are always
  /// load flows, so they are judged against [budgetMs].
  static void stop(String name, Stopwatch timer) {
    if (!enabled) return;
    timer.stop();
    _report(name, timer.elapsedMilliseconds, budgeted: true);
  }

  /// Measures an async action and reports its duration under [name]. The
  /// action's error still propagates; the timing is recorded either way.
  static Future<T> measure<T>(String name, Future<T> Function() action) async {
    final timer = start();
    try {
      return await action();
    } finally {
      stop(name, timer);
    }
  }

  static void _report(String name, int ms, {required bool budgeted}) {
    final verdict = budgeted
        ? ' (budget ${budgetMs}ms: ${ms > budgetMs ? 'OVER budget' : 'PASS'})'
        : '';
    debugPrint('[timing] $name=${ms}ms$verdict');
  }
}
