import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder.dart';

/// {@template session_observer}
/// Optional [NavigatorObserver] that gives Session Recorder explicit
/// navigation signals.
///
/// Create it once after `SessionRecorder.init` and add it beside existing
/// observers. Multiple Navigators may each use their own
/// [SessionNavigatorObserver]; do not reuse one instance across Navigators.
/// The observer does not define the capture boundary and is not required for
/// capture to work.
///
/// {@endtemplate}
class SessionNavigatorObserver extends NavigatorObserver {
  SessionNavigatorObserver() {
    SessionRecorder.engine.controller.registerObserver(this);
  }

  bool _isAttached = false;

  /// True if this observer was ever attached to a Navigator and is now detached.
  @pragma('vm:prefer-inline')
  bool get isDisposed => _isAttached && navigator == null;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _setAttached();
    _handleTransition(route, AnimationStatus.completed);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _setAttached();
    _handleTransition(route, AnimationStatus.dismissed);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _setAttached();
    if (newRoute == null) return;
    _handleTransition(newRoute, AnimationStatus.completed);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _setAttached();
  }

  @pragma('vm:prefer-inline')
  void _setAttached() => _isAttached = true;

  /// Reports navigation and waits for `route`'s animation to settle.
  void _handleTransition(
    Route<dynamic> route,
    AnimationStatus terminalStatus,
  ) {
    final controller = SessionRecorder.engine.controller;
    controller.beginNavigation();

    final animation = (route is TransitionRoute) ? route.animation : null;

    bool didFinish = false;

    void finish() {
      if (didFinish) return;
      didFinish = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.finishNavigation();
      });
    }

    if (animation == null || animation.status == terminalStatus) {
      finish();
      return;
    }

    late final AnimationStatusListener listener;
    listener = (AnimationStatus status) {
      if (status == terminalStatus) {
        animation.removeStatusListener(listener);
        finish();
      }
    };

    animation.addStatusListener(listener);

    if (animation.status == terminalStatus) {
      animation.removeStatusListener(listener);
      finish();
    }
  }
}
