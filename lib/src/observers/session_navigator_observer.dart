import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder.dart';

/// {@template session_observer}
/// Listens to navigation events and schedules a widget tree capture once
/// each route transition has fully settled.
///
/// ### Standard Navigator
/// ```dart
/// SessionRecorder.observer(
///   builder: (observer) => MaterialApp(
///     navigatorObservers: [observer],
///     home: const HomeScreen(),
///   ),
/// );
/// ```
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
    _handleCapture(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _setAttached();
    if (previousRoute == null) return;
    _handleCapture(previousRoute, waitForRoute: route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _setAttached();
    if (newRoute == null) return;
    _handleCapture(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _setAttached();
  }

  @pragma('vm:prefer-inline')
  void _setAttached() => _isAttached = true;

  /// Suppresses auto-captures and waits for `route`'s animation to settle,
  /// then captures the tree from the route's subtree element.
  void _handleCapture(Route<dynamic> route, {Route<dynamic>? waitForRoute}) {
    SessionRecorder.engine.context.setCurrentlyNavigating();
    SessionRecorder.engine.controller.interrupt();

    final routeToWait = waitForRoute ?? route;
    final animation = (routeToWait is TransitionRoute)
        ? routeToWait.animation
        : null;

    void capture() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final elementFromContext = _contextOf(route);

        SessionRecorder.engine.context.setCurrentRouteElement(
          elementFromContext,
        );

        if (elementFromContext == null) return;

        SessionRecorder.engine.context.captureTree(true);
      });
    }

    if (animation == null ||
        animation.status == AnimationStatus.completed ||
        animation.status == AnimationStatus.dismissed) {
      capture();
      return;
    }

    late final AnimationStatusListener listener;
    listener = (AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
        capture();
      }
    };

    animation.addStatusListener(listener);
  }

  /// Finds the best available `[Element]` from the `route` subtree context.
  ///
  /// ### Priority:
  /// 1. `[ModalRoute.subtreeContext]` : the route's own mounted element.
  /// 2. `[NavigatorObserver.navigator?.context]` : fallback if subtree not yet
  ///   mounted.
  /// 3. null : `[_contextOf]` falls back to the global root.
  Element? _contextOf(Route<dynamic> route) {
    if (route is ModalRoute) {
      final context = route.subtreeContext;
      if (context is Element && context.mounted) return context;
    }

    final navigatorContext = route.navigator?.context;
    if (navigatorContext is Element && navigatorContext.mounted) {
      return navigatorContext;
    }

    return null;
  }
}
