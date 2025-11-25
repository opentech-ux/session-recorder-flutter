import 'package:flutter/widgets.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/services/route_tracker.dart';

class SessionRecorderObserver extends RouteObserver<PageRoute<dynamic>> {
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
