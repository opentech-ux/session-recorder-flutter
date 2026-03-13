import 'package:flutter/widgets.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/services/route_tracker.dart';

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
class SessionRecorderObserver extends RouteObserver<PageRoute<dynamic>> {
  /// {@macro session_observer}
  SessionRecorderObserver();

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    RouteTracker.instance.handleRouting(route, NavigationType.push);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    RouteTracker.instance.handleRouting(
      route,
      NavigationType.pop,
      oldRoute: previousRoute,
    );

    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    RouteTracker.instance.handleRouting(
      newRoute,
      NavigationType.replace,
      oldRoute: oldRoute,
    );

    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    RouteTracker.instance.handleRouting(
      route,
      NavigationType.remove,
      oldRoute: previousRoute,
    );

    super.didRemove(route, previousRoute);
  }
}
