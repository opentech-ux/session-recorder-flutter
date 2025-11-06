import 'dart:async';

typedef SessionCallback = Future<void> Function();

/// Singleton that manages a periodic session-record timer.
///
/// Use the factory constructor [SessionRecordTimer()] to obtain the single
/// shared instance.
///
/// - Call `init()` to start the service and `dispose()` to stop and release
///   resources when no longer needed.
class SessionRecordTimer {
  static final SessionRecordTimer _instance = SessionRecordTimer._internal();
  factory SessionRecordTimer() => _instance;
  SessionRecordTimer._internal();

  /// The active periodic [Timer], or `null` if no timer is running.
  ///
  /// This is the timer returned by `Timer.periodic(...)` and is canceled by
  /// calling `stop()` or `dispose()`. Keep it private to avoid external
  /// interference with the timer lifecycle.
  Timer? _timer;

  /// The interval used for the periodic timer ticks.
  ///
  /// __Defaults to 10 seconds in this implementation.__
  final Duration _interval = Duration(seconds: 10);

  /// Indicates whether the timer subsystem has been initialized.
  ///
  /// Prevents double-initialization. `init()` should flip this flag to [true]
  /// and `dispose()` should set it back to [false].
  bool _initialized = false;

  /// Callback invoked on every timer tick.
  ///
  /// If this is [null], `onInvokeSessionRecordTimer()` will refuse to start
  /// timer.
  /// Assign a callback before calling `init()` or `onInvokeSessionRecordTimer()`.
  SessionCallback? onSessionRecord;

  /// Initializes the session record timer subsystem.
  ///
  /// If already initialized, this call is a no-op. After initialization,
  /// the periodic session-record timer will start (if `onSessionRecord` is set).
  void init() {
    if (_initialized) return;
    _initialized = true;
    _startSessionRecordTimer();
  }

  /// Disposes the session record timer subsystem.
  ///
  /// Stops the periodic timer and marks the subsystem as uninitialized.
  /// After calling dispose, you must call `init()` again before restarting.
  void dispose() {
    if (!_initialized) return;
    _initialized = false;
    stop();
  }

  /// Public trigger to (re)start the periodic session-record timer.
  ///
  /// Can be called externally when you need to ensure the periodic recording
  /// timer is running immediately.
  void onInvokeSessionRecordTimer() => _startSessionRecordTimer();

  /// Starts the periodic session-record timer if it is not already running.
  ///
  /// The timer will call `onSessionRecord` on each tick. `onSessionRecord` must
  /// have the signature `void Function(Timer)` (or `SessionCallback`).
  void _startSessionRecordTimer() {
    if (_timer?.isActive ?? false) return;

    if (onSessionRecord == null) return;

    _timer = Timer.periodic(_interval, (_) => onSessionRecord?.call());
  }

  /// Stops the periodic session-record timer and clears its reference.
  ///
  /// Useful when the inactivity tracking should be paused
  /// (e.g., app goes to background).
  void stop() {
    if (_timer == null) return;

    _timer?.cancel();
    _timer = null;
  }
}
