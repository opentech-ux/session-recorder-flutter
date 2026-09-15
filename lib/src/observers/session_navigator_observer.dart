import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/utils/recorder_callback.dart';

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
  ///{@macro session_observer}
  SessionNavigatorObserver() {
    runRecorderCallback('navigation observer registration', () {
      SessionRecorder.engine.controller.registerObserver(this);
    });
  }

  bool _isAttached = false;
  final Map<Route<dynamic>, VoidCallback> _pendingTransitions = Map.identity();

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
    if (oldRoute != null) _finishPending(oldRoute);
    if (newRoute == null) return;
    _handleTransition(newRoute, AnimationStatus.completed);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _setAttached();
    _finishPending(route);
  }

  @pragma('vm:prefer-inline')
  void _setAttached() => _isAttached = true;

  /// Reports navigation and waits for `route`'s animation to settle.
  void _handleTransition(Route<dynamic> route, AnimationStatus terminalStatus) {
    if (!runRecorderCallback('navigation transition', () {
      _startTransition(route, terminalStatus);
    })) {
      _finishPending(route);
    }
  }

  void _finishPending(Route<dynamic> route) {
    final finish = _pendingTransitions.remove(route);
    if (finish != null) runRecorderCallback('navigation cleanup', finish);
  }

  void _startTransition(Route<dynamic> route, AnimationStatus terminalStatus) {
    // Superseding a wait closes only this route's previous transition.
    _finishPending(route);
    final controller = SessionRecorder.engine.controller;

    final animation = (route is TransitionRoute) ? route.animation : null;

    bool didFinish = false;
    AnimationStatusListener? listener;

    void finish() {
      if (didFinish) return;
      didFinish = true;
      final pendingListener = listener;
      if (pendingListener != null) {
        runRecorderCallback('navigation listener cleanup', () {
          animation?.removeStatusListener(pendingListener);
        });
      }
      _pendingTransitions.remove(route);

      // Keep the existing frame boundary; a replacement begins before this
      // decrement, so it cannot briefly complete all navigation transitions.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        runRecorderCallback('navigation completion', controller.finishNavigation);
      });
    }

    _pendingTransitions[route] = finish;

    // Register cleanup before begin can fail while draining SDK collectors.
    controller.beginNavigation();

    if (animation == null || animation.status == terminalStatus) {
      finish();
      return;
    }

    listener = (AnimationStatus status) {
      if (status == terminalStatus) {
        runRecorderCallback('navigation animation completion', finish);
      }
    };

    animation.addStatusListener(listener);

    if (animation.status == terminalStatus) {
      finish();
    }
  }
}
