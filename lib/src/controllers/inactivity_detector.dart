// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/utils/session_logger.dart';

enum InactivityState { active, inactive }

/// Tracks user inactivity by expecting periodic [ping] calls.
///
/// Every time the user interacts (tap, scroll, navigation) the controller
/// calls [ping], which resets the countdown. If [timeout] passes without
/// a [ping], [onInactive] fires. The next [ping] after that fires [onActive].
class InactivityDetector {
  /// The inactivity interval used to decide when the user is idle.
  ///
  ///  __Defaults to 30 seconds.__
  final Duration _interval = Duration(seconds: 30);

  /// Callback invoked when inactivity is detected (when the timer completes).
  ///
  /// Assign before calling `init()` if you want to react to inactivity.
  final VoidCallback onInactive;

  /// Callback invoked when activity is detected after the system was
  /// previously considered inactive.
  ///
  /// Called once when transitioning from `_isInactive == true` to
  /// `_isInactive == false`.
  final VoidCallback onActive;

  InactivityDetector({required this.onInactive, required this.onActive});

  InactivityState _state = InactivityState.active;
  InactivityState get state => _state;
  bool get isActive => _state == InactivityState.active;

  /// The active single-shot `[Timer]`, or `null` if there is currently no
  /// countdown running.
  Timer? _timer;

  /// Timestamp of the last time the timer was reset.
  ///
  /// Used together with `_throttleDuration` to limit how often the timer is
  /// restarted (avoids expensive cancel/start operations on high-frequency
  /// pointer events).
  // DateTime? _lastReset;

  /// Minimum time between actual timer resets (throttling window).
  ///
  /// If a reset is requested within this duration from the previous reset,
  /// the request will be ignored.
  ///
  /// __Defaults to 200 milliseconds.__
  // final Duration _throttleDuration = Duration(milliseconds: 200);

  /// Whether the timer subsystem has been initialized.
  ///
  /// Prevents double initialization. `init()` should set this to `[true]` and
  /// `dispose()` should set it back to `[false]`.
  // bool _initialized = false;

  /// Current inactivity state.
  ///
  /// - `[true]` means the timer completed and the system considers the user
  ///   inactive.
  /// - `[false]` means the user is currently considered active.
  // bool isInactive = false;

  /// Initializes the inactivity timer.
  ///
  /// Ensures the timer is only started once.
  /// This must be called before using the timer.
  // void init() {
  //   if (_initialized) return;
  //   _initialized = true;
  //   _startInactivityDetector();
  // }

  /// Pings every user interaction
  void ping() {
    if (_state == InactivityState.inactive) {
      _state = InactivityState.active;
      SessionLogger.mlog(">> [ Inactivity active ]");
      onActive();
    }

    _reset();
  }

  /// Starts the inactivity timer.
  void start() => _reset();

  /// Manually triggers a reset of the inactivity timer.
  ///
  /// This should be invoked whenever user activity is detected.
  /// If throttling conditions apply, the reset may be skipped.
  // void onInvokeInactivityDetector() => _restartInactivityDetector();

  /// Starts the inactivity countdown if not already running.
  void _reset() {
    // if (_timer != null && _timer!.isActive) return;

    _timer?.cancel();
    _timer = Timer(_interval, () {
      if (_state == InactivityState.inactive) return;
      _state = InactivityState.inactive;

      SessionLogger.mlog(">> [ Inactivity after ${_interval.inSeconds}s ]");
      onInactive();
    });
  }

  /// Stops the inactivity timer and clears its reference.
  void stop() {
    // if (_timer != null) {
    _timer?.cancel();
    _timer = null;
    // }
  }

  /// Restarts the inactivity timer based on user activity.
  ///
  /// Resets inactivity state if needed and triggers `[onActive]`.
  ///
  /// Includes a throttle mechanism to avoid too frequent resets
  /// (e.g., during continuous pointer movement events).
  // void _restartInactivityDetector() {
  //   final DateTime now = DateTime.now();

  //   if (_lastReset != null && now.difference(_lastReset!) < _throttleDuration) {
  //     return;
  //   }

  //   _lastReset = now;

  //   if (isInactive) {
  //     isInactive = false;
  //     onActive?.call();
  //   }

  //   _timer?.cancel();
  //   _timer = Timer(_interval, () {
  //     isInactive = true;
  //     onInactive?.call();
  //   });
  // }

  /// Disposes all internal resources.
  ///
  /// After calling `[dispose]`, this timer manager must not be used again
  /// unless `[init]` is called to reinitialize.
  // void dispose() {
  //   if (!_initialized) return;
  //   _initialized = false;

  //   stop();
  // }
}
