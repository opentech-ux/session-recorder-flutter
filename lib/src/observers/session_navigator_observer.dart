import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder.dart';

/// {@template session_observer}
/// Optional observer that reports navigation transitions to the session
/// recorder and coordinates a capture after those transitions have settled.
///
/// Add it only when precise post-navigation captures are wanted:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [
///     SessionNavigatorObserver(),
///   ],
///   home: const HomeScreen(),
/// )
/// ```
///
/// It is not required for initial capture, gestures, scrolls, or ordinary UI
/// mutations.
///
/// ### GoRouter with ShellRoutes
/// You may attach multiple observers (e.g. when using multiple `[ShellRoute]`
/// navigators from `[GoRouter]` package).
///
/// ```dart
/// GoRouter(
///   observers: [SessionNavigatorObserver()],
///   routes: [
///     ShellRoute(
///       observers: [SessionNavigatorObserver()],
///       routes: [...],
///     ),
///   ],
/// );
/// ```
/// All instances share the same `[SessionRecorder]` singleton.
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
