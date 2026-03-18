import 'package:meta/meta.dart';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';

/// Internal contract for recording tree snapshots and navigations
@internal
abstract interface class SessionControllerInternal {
  void registerObserver(SessionNavigatorObserver observer);
  bool get isNavigationAttached;

  Element? get currentRouteElement;
  void setCurrentRouteElement(Element? element);

  void captureTree(bool comesFromNavigation);
  void captureCurrentNavigation();

  void startReporting();
  void stopReporting();
}
