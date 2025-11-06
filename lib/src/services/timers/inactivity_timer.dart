import 'dart:async';

import 'package:flutter/material.dart';

/// Singleton that manages a single-shot inactivity timer.
///
/// Use the factory constructor [InactivityTimer()] to obtain the single
/// shared instance.
///
/// Call `init()` to enable the service and `dispose()` to stop it and release
/// resources when no longer needed.
class InactivityTimer {
  static final InactivityTimer _instance = InactivityTimer._internal();
  factory InactivityTimer() => _instance;
  InactivityTimer._internal();

  /// The active single-shot [Timer], or `null` if there is currently no
  /// countdown running.
  ///
  /// This timer is created with `Timer(_interval, ...)` and is canceled when
  /// `stop()` or `dispose()` is called, or when the timer is restarted.
  Timer? _timer;

  /// The inactivity interval used to decide when the user is idle.
  ///
  /// When no activity is detected for this duration, the timer completes and
  /// `onInactive()` is invoked.
  ///
  ///  __Defaults to 30 seconds.__
  final Duration _interval = Duration(seconds: 30);

  /// Timestamp of the last time the timer was reset.
  ///
  /// Used together with `_throttleDuration` to limit how often the timer is
  /// restarted (avoids expensive cancel/start operations on high-frequency
  /// pointer events).
  DateTime? _lastReset;

  /// Minimum time between actual timer resets (throttling window).
  ///
  /// If a reset is requested within this duration from the previous reset,
  /// the request will be ignored.
  ///
  /// __Defaults to 200 milliseconds.__
  final Duration _throttleDuration = Duration(milliseconds: 200);

  /// Whether the timer subsystem has been initialized.
  ///
  /// Prevents double initialization. `init()` should set this to [true] and
  /// `dispose()` should set it back to [false].
  bool _initialized = false;

  /// Current inactivity state.
  ///
  /// - [true] means the timer completed and the system considers the user
  ///   inactive.
  /// - [false] means the user is currently considered active.
  bool _isInactive = false;

  /// Callback invoked when inactivity is detected (when the timer completes).
  ///
  /// Assign before calling `init()` if you want to react to inactivity.
  VoidCallback? onInactive;

  /// Callback invoked when activity is detected after the system was
  /// previously considered inactive.
  ///
  /// Called once when transitioning from `_isInactive == true` to
  /// `_isInactive == false`.
  VoidCallback? onActive;

  /// Initializes the inactivity timer.
  ///
  /// Ensures the timer is only started once.
  /// This must be called before using the timer.
  void init() {
    if (_initialized) return;
    _initialized = true;
    _startInactivityTimer();
  }

  /// Manually triggers a reset of the inactivity timer.
  ///
  /// This should be invoked whenever user activity is detected.
  /// If throttling conditions apply, the reset may be skipped.
  void onInvokeInactivityTimer() => _restartInactivityTimer();

  /// Starts the inactivity countdown if not already running.
  ///
  /// When the timer completes, the app is considered inactive and
  /// [onInactive] will be triggered.
  void _startInactivityTimer() {
    if (_timer != null && _timer!.isActive) return;

    _timer = Timer(_interval, () {
      _isInactive = true;
      onInactive?.call();
    });
  }

  /// Restarts the inactivity timer based on user activity.
  ///
  /// Resets inactivity state if needed and triggers [onActive].
  ///
  /// Includes a throttle mechanism to avoid too frequent resets
  /// (e.g., during continuous pointer movement events).
  void _restartInactivityTimer() {
    final DateTime now = DateTime.now();

    if (_lastReset != null && now.difference(_lastReset!) < _throttleDuration) {
      return;
    }

    _lastReset = now;

    if (_isInactive) {
      _isInactive = false;
      onActive?.call();
    }

    _timer?.cancel();
    _timer = Timer(_interval, () {
      _isInactive = true;
      onInactive?.call();
    });
  }

  /// Stops the inactivity timer and clears its reference.
  ///
  /// Useful when the inactivity tracking should be paused
  /// (e.g., app goes to background).
  void stop() {
    if (_timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Disposes all internal resources.
  ///
  /// After calling [dispose], this timer manager must not be used again
  /// unless [init] is called to reinitialize.
  void dispose() {
    if (!_initialized) return;
    _initialized = false;

    stop();
  }
}
