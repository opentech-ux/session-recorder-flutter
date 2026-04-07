import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';

/// Internal contract for recording tree snapshots and navigations
@internal
abstract interface class SessionControllerInternal {
  void registerObserver(SessionNavigatorObserver observer);
  bool get isNavigationAttached;

  Element? get currentRouteElement;
  void setCurrentRouteElement(Element? element);

  void captureTree(bool comesFromNavigation);
  void setCurrentlyNavigating();

  ValueListenable<LomAbstract?>? get notifier;

  void startReporting();
  void stopReporting();

  void onInterrupt(VoidCallback? onInterrupt);
  void interrupt();
}
