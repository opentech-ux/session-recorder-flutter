import 'package:flutter/foundation.dart';

import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';

/// Internal contract for managing lifecycle, timers, and navigation state.
@internal
abstract interface class SessionControllerInternal {
  void registerObserver(SessionNavigatorObserver observer);
  bool get isNavigationAttached;

  void startReporting();
  void stopReporting();
  void pingInactivity() {}

  void onInterrupt(VoidCallback? onInterrupt);
  void interrupt();
}

class NoOpController implements SessionControllerInternal {
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
