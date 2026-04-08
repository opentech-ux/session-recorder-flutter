import 'dart:async';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

enum InactivityState { active, inactive }

/// Tracks user inactivity by expecting periodic `ping` calls.
///
/// Every time the user interacts (tap, scroll, navigation) the controller
/// calls `ping`, which resets the countdown. If [timeout] passes without
/// a `ping`, `[onInactive]` fires. The next `ping` after that fires `[onActive]`.
class InactivityDetector {
  /// The inactivity interval used to decide when the user is idle.
  final Duration _interval = Duration(seconds: 30);

  /// Callback invoked when inactivity is detected (when the timer completes).
  final VoidCallback onInactive;

  /// Callback invoked when activity is detected after the system was
  /// previously considered inactive.
  final VoidCallback onActive;

  InactivityDetector({required this.onInactive, required this.onActive});

  InactivityState _state = InactivityState.active;
  InactivityState get state => _state;

  /// The active single-shot `[Timer]`, or `null` if there is currently no
  /// countdown running.
  Timer? _timer;

  /// Call on every user interaction.
  void ping() {
    if (_state == InactivityState.inactive) {
      _state = InactivityState.active;
      SessionLogger.verbose("Inactivity active");
      onActive();
    }

    _reset();
  }

  /// Starts the inactivity timer.
  void start() => _reset();

  /// Starts the inactivity countdown if not already running.
  void _reset() {
    _timer?.cancel();
    _timer = Timer(_interval, () {
      if (_state == InactivityState.inactive) return;
      _state = InactivityState.inactive;

      SessionLogger.verbose("Inactivity after ${_interval.inSeconds}s");
      onInactive();
    });
  }

  /// Cancels the inactivity timer and clears its reference.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
