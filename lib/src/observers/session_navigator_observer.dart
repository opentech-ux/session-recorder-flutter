import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/utils/recorder_callback.dart';

/// {@template session_observer}
/// Recommended, optional [NavigatorObserver] for explicit navigation signals
/// and automatic hashed path segments from Route.settings.name. A configured
/// screenNameProvider overrides this metadata, never the navigation signals.
/// Automatic selection is local and best-effort. PopupRoute overlays preserve
/// the screen context; unnamed screens mean unknown. Use screenNameProvider
/// for precise logical screen context with complex or multiple Navigators.
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
  Route<dynamic>? _observedRoute;
  final Map<Route<dynamic>, VoidCallback> _pendingTransitions = Map.identity();

  /// True if this observer was ever attached to a Navigator and is now detached.
  @pragma('vm:prefer-inline')
  bool get isDisposed => _isAttached && navigator == null;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    SessionRecorder.engine.context.refreshScreenName();
    super.didPush(route, previousRoute);
    _setAttached();
    _observeRoute(route);
    _handleTransition(route, AnimationStatus.completed);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    SessionRecorder.engine.context.refreshScreenName();
    super.didPop(route, previousRoute);
    _setAttached();
    if (identical(route, _observedRoute)) {
      _observeRoute(previousRoute);
    }
    _handleTransition(route, AnimationStatus.dismissed);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    SessionRecorder.engine.context.refreshScreenName();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _setAttached();
    if (oldRoute != null && identical(oldRoute, _observedRoute)) {
      _observeRoute(newRoute);
    }
    if (oldRoute != null) _finishPending(oldRoute);
    if (newRoute == null) return;
    _handleTransition(newRoute, AnimationStatus.completed);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    SessionRecorder.engine.context.refreshScreenName();
    super.didRemove(route, previousRoute);
    _setAttached();
    if (identical(route, _observedRoute)) {
      _observeRoute(previousRoute);
    }
    _finishPending(route);
  }

  // No super call: older supported Flutter versions do not expose this hook.
  // It reconciles the local screen only, without starting a transition.
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    SessionRecorder.engine.context.refreshScreenName();
    _observeRoute(topRoute);
  }

  void _observeRoute(Route<dynamic>? route) {
    if (SessionRecorder.engine.config.screenNameProvider != null) return;
    // Preserve the underlying screen for popups, without discovering a stack.
    if (route is PopupRoute || identical(route, _observedRoute)) return;
    runRecorderCallback('observed route', () {
      _observedRoute = route;
      SessionRecorder.engine.context.observeRouteName(route?.settings.name);
    });
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
        runRecorderCallback(
            'navigation completion', controller.finishNavigation);
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
