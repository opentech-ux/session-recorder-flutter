import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/session/session_controller_internal.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';

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
  final SessionControllerInternal _controller;

  SessionNavigatorObserver({SessionRecorder? recorder})
    : _controller = (recorder ?? SessionRecorder.instance).controller {
    _controller.registerObserver(this);
  }

  bool _isAttached = false;
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
    _handleCapture(previousRoute);
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

  void _setAttached() => _isAttached = true;

  void _handleCapture(Route<dynamic> route) {
    _controller.captureCurrentNavigation();

    final animation = (route as TransitionRoute).animation;

    void capture() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final elementFromContext = _contextOf(route);

        _controller.setCurrentRouteElement(elementFromContext);

        if (elementFromContext == null) return;

        debugPrint(">> OBSERVER CAPTURE");

        _controller.captureTree(true);
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
