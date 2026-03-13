part of '../session_recorder_core.dart';

/// {@template session_observer}
/// A lightweight navigation observer used to capture navigation events
/// and delegate them to the internal `[RouteTracker]`.
///
/// The observer itself **does not contain any tracking logic**.
/// Its only responsibility is to forward each event to the central
/// tracking engine: `[RouteTracker]`.
///
/// **!! It should not be called without first initializing the package with
/// `SessionRecorder.instance.init()` !!**
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:session_recorder_flutter/session_recorder.dart';
///
/// MaterialApp(
///   navigatorObservers: [
///     SessionRecorderObserver(),
///   ],
/// [...]
/// )
/// ```
///
/// You may attach multiple observers (e.g., when using multiple
/// `[ShellRoute]` navigators from `[GoRouter]` package). All of them will safely
/// report their events to the same global `[RouteTracker]`.
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:session_recorder_flutter/session_recorder.dart';
///
/// MaterialApp.router(
///   routerConfig: GoRouter(
///     observers: [SessionRecorderObserver()],
///     routes: [...],
///   ),
/// );
/// ```
///
/// See also :
///   - `[SessionRecorder]`: Main service coordinator for session recording
/// and interaction capture.
///   - `[RouteTracker]`: Central navigation tracking engine used internally
/// by the package.
/// {@endtemplate}
class SessionNavigatorObserver extends NavigatorObserver {
  final SessionRecorder _recorder;

  SessionNavigatorObserver({SessionRecorder? recorder})
    : _recorder = recorder ?? SessionRecorder.instance {
    _recorder.observer = this;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is! PageRoute) return;
    _handleCapture(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute == null) return;
    if (previousRoute is! PageRoute) return;
    _handleCapture(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute == null) return;
    if (newRoute is! PageRoute) return;
    _handleCapture(newRoute);
  }

  void _handleCapture(PageRoute<dynamic> route) {
    final animation = (route as TransitionRoute).animation;

    void capture() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final elementFromContext = _contextOf(route);
        _recorder._captureTree(elementFromContext);
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

  /// Finds the best available `[Element]` from the `route`.
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
