import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_reporter.dart';

import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';

/// Internal contract for managing lifecycle, timers, and navigation state.
@internal
abstract interface class SessionRecorderController {
  void registerObserver(SessionNavigatorObserver observer);
  bool get isNavigationAttached;
  void beginNavigation();
  void finishNavigation(Element? routeElement);

  void startReporting();
  void stopReporting();
  void dispose();
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
  void beginNavigation() {}
  @override
  void finishNavigation(Element? routeElement) {}
  @override
  void interrupt() {}
  @override
  void onInterrupt(VoidCallback? onInterrupt) {}
  @override
  void stopReporting() {}
  @override
  void dispose() {}
  @override
  void pingInactivity() {}
}

@internal
class ControllerImpl implements SessionRecorderController {
  final SessionRecorderEngineInternal _engine;
  ControllerImpl(this._engine);

  final List<SessionNavigatorObserver> _observers = [];
  int _pendingNavigations = 0;
  Element? _pendingRouteElement;

  VoidCallback? _onCollectorInterrupt;

  @override
  bool get isNavigationAttached {
    _removeDisposedObservers();
    return _observers.any((o) => o.navigator != null);
  }

  late final InactivityDetector _inactivity = InactivityDetector(
    onActive: startReporting,
    onInactive: stopReporting,
  );
  SessionRecorderReporter? _reporter;

  SessionRecorderReporter get _activeReporter =>
      _reporter ??= SessionRecorderReporter(_engine);

  @override
  void registerObserver(SessionNavigatorObserver observer) {
    _removeDisposedObservers();
    if (!_observers.contains(observer)) _observers.add(observer);
  }

  @override
  void beginNavigation() {
    if (_pendingNavigations == 0) {
      _pendingRouteElement = null;
      _engine.context.setCurrentlyNavigating();
      interrupt();
    }

    _pendingNavigations++;
  }

  @override
  void finishNavigation(Element? routeElement) {
    if (_pendingNavigations == 0) return;

    if (routeElement != null &&
        (_pendingRouteElement == null ||
            _elementDepth(routeElement) >
                _elementDepth(_pendingRouteElement!))) {
      _pendingRouteElement = routeElement;
    }

    _pendingNavigations--;
    if (_pendingNavigations > 0) return;

    final target = _pendingRouteElement;
    _pendingRouteElement = null;

    if (target != null) {
      _engine.context.setCurrentRouteElement(target);
    }
    _engine.context.captureTree(true);
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
  void onInterrupt(VoidCallback? onInterrupt) =>
      _onCollectorInterrupt = onInterrupt;

  @override
  void dispose() {
    _onCollectorInterrupt = null;
    stopReporting();
    _reporter?.close();
    _reporter = null;
    _observers.clear();
    _pendingNavigations = 0;
    _pendingRouteElement = null;
  }

  int _elementDepth(Element element) {
    var depth = 0;
    element.visitAncestorElements((_) {
      depth++;
      return true;
    });
    return depth;
  }

  /// Clears observers detached from their Navigator.
  void _removeDisposedObservers() {
    _observers.removeWhere((observer) => observer.isDisposed);
  }
}
