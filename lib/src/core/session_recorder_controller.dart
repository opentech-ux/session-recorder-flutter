import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_reporter.dart';

import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

/// Internal contract for managing lifecycle, timers, and navigation state.
@internal
abstract interface class SessionRecorderController {
  void registerObserver(SessionNavigatorObserver observer);
  void beginNavigation();
  void finishNavigation();

  void startReporting();
  void stopReporting();
  void dispose();
  void pingInactivity() {}

  void onInterrupt(
    VoidCallback? onInterrupt, {
    VoidCallback? onNavigationInterrupt,
  });
  void interrupt();
}

@internal
class NoOpController implements SessionRecorderController {
  NoOpController._();
  static final _instance = NoOpController._();
  factory NoOpController() => _instance;

  @override
  void registerObserver(SessionNavigatorObserver o) {}
  @override
  void beginNavigation() {}
  @override
  void finishNavigation() {}
  @override
  void startReporting() {}
  @override
  void interrupt() {}
  @override
  void onInterrupt(
    VoidCallback? onInterrupt, {
    VoidCallback? onNavigationInterrupt,
  }) {}
  @override
  void stopReporting() {}
  @override
  void dispose() {}
  @override
  void pingInactivity() {}
}

@internal
class ControllerImpl implements SessionRecorderController {
  final SessionRecorderEngine _engine;
  ControllerImpl(this._engine);

  final List<SessionNavigatorObserver> _observers = [];
  int _activeNavigationTransitions = 0;
  bool _isDisposed = false;

  VoidCallback? _onCollectorInterrupt;
  VoidCallback? _onNavigationInterrupt;

  late final InactivityDetector _inactivity = InactivityDetector(
    onActive: startReporting,
    onInactive: stopReporting,
  );
  SessionRecorderReporter? _reporter;

  SessionRecorderReporter get _activeReporter =>
      _reporter ??= SessionRecorderReporter(_engine);

  @override
  void registerObserver(SessionNavigatorObserver observer) {
    if (_isDisposed) return;
    _removeDisposedObservers();
    if (!_observers.contains(observer)) _observers.add(observer);
  }

  @override
  void beginNavigation() {
    if (_isDisposed) return;

    final isFirstTransition = _activeNavigationTransitions == 0;
    _activeNavigationTransitions += 1;

    if (!isFirstTransition) return;

    _engine.context.setCurrentlyNavigating();
    (_onNavigationInterrupt ?? _onCollectorInterrupt)?.call();
  }

  @override
  void finishNavigation() {
    if (_isDisposed || _activeNavigationTransitions == 0) return;

    _activeNavigationTransitions -= 1;
    if (_activeNavigationTransitions != 0) return;

    try {
      _engine.context.captureTree(true);
    } catch (error, stackTrace) {
      SessionLogger.error(
        "Navigation capture failed",
        error,
        stackTrace,
      );
    }
  }

  @override
  void pingInactivity() => _inactivity.ping();

  @override
  void startReporting() {
    _activeReporter.start();
    _inactivity.start();
  }

  @override
  void stopReporting() {
    _reporter?.stop();
    _inactivity.stop();
  }

  @override
  void interrupt() => _onCollectorInterrupt?.call();

  @override
  void onInterrupt(
    VoidCallback? onInterrupt, {
    VoidCallback? onNavigationInterrupt,
  }) {
    _onCollectorInterrupt = onInterrupt;
    _onNavigationInterrupt = onNavigationInterrupt;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _activeNavigationTransitions = 0;
    _onCollectorInterrupt = null;
    _onNavigationInterrupt = null;
    stopReporting();
    _reporter?.close();
    _reporter = null;
    _observers.clear();
  }

  /// Clears observers detached from their Navigator.
  void _removeDisposedObservers() {
    _observers.removeWhere((observer) => observer.isDisposed);
  }
}
