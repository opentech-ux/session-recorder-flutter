import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_reporter.dart';

import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';

/// Internal contract for managing lifecycle, timers, and navigation state.
@internal
abstract interface class SessionRecorderController {
  void registerObserver(SessionNavigatorObserver observer);
  bool get isNavigationAttached;

  void startReporting();
  void stopReporting();
  void pingInactivity() {}

  void onInterrupt(VoidCallback? onInterrupt);
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
  void startReporting() {}
  @override
  bool get isNavigationAttached => false;
  @override
  void interrupt() {}
  @override
  void onInterrupt(VoidCallback? onInterrupt) {}
  @override
  void stopReporting() {}
  @override
  void pingInactivity() {}
}

@internal
class ControllerImpl implements SessionRecorderController {
  final SessionRecorderEngine _engine;
  ControllerImpl(this._engine);

  final List<SessionNavigatorObserver> _observers = [];

  VoidCallback? _onCollectorInterrupt;

  @override
  bool get isNavigationAttached => _observers.any((o) => o.navigator != null);

  late final InactivityDetector _inactivity = InactivityDetector(
    onActive: startReporting,
    onInactive: stopReporting,
  );
  late final SessionRecorderReporter _reporter = SessionRecorderReporter(
    _engine,
  );

  @override
  void registerObserver(SessionNavigatorObserver observer) {
    _observers.removeWhere((obs) => obs.isDisposed);
    if (!_observers.contains(observer)) _observers.add(observer);
  }

  @override
  void pingInactivity() => _inactivity.ping();

  @override
  void startReporting() {
    _reporter.start();
    _inactivity.start();
  }

  @override
  void stopReporting() {
    _reporter.stop();
    _inactivity.stop();
  }

  @override
  void interrupt() => _onCollectorInterrupt?.call();

  @override
  void onInterrupt(VoidCallback? onInterrupt) =>
      _onCollectorInterrupt = onInterrupt;
}
