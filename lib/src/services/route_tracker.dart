import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/utils/serialize_tree_utils.dart';
import 'package:session_recorder_flutter/src/utils/session_logger.dart';

import '../models/models.dart';

typedef CaptureTreeHandler = void Function();
typedef InitSessionHandler = bool Function();

/// {@template route_tracker}
/// Central navigation tracking responsible for analyzing,
/// registering, updating and removing routes as the user navigates.
///
/// Currently, only `[ModalRoute]` instances are accepted, ensuring strict
/// control over the types of routes being processed and preventing
/// potential errors in the future.
///
/// This behavior guarantees that the navigation tracking system remains
/// stable and consistent by allowing only compatible routes to enter
/// the management flow from its contexts.
/// {@endtemplate}
class RouteTracker {
  /// {@macro route_tracker}
  RouteTracker._internal();
  static final RouteTracker instance = RouteTracker._internal();
  factory RouteTracker() => instance;

  /// Stack that stores all active routes currently being tracked.
  final Map<Route<dynamic>, RouteRecorded> _routes = {};

  /// Indicates whether the `[RouterTracker]` is currently tracking.
  bool isRouting = false;

  /// Stores the last detected navigation type.
  NavigationType _lastNavigationType = NavigationType.none;

  /// Handler coming from `[SessionRecorder]` to capture the widget tree.
  CaptureTreeHandler? _captureTreeHandler;

  /// Handler coming from `[SessionRecorder]` to indicate if it's initialized.
  InitSessionHandler? _isInitializedSession;

  /// Timer to debounce every route coming from the [SessionRecorderObserver].
  Timer? _debounceRoute;

  void registerTreeHandler(CaptureTreeHandler tree) =>
      _captureTreeHandler = tree;
  void registerInitSessionHandler(InitSessionHandler init) =>
      _isInitializedSession = init;

  bool get isSessionServiceInitialized =>
      _isInitializedSession?.call() ?? false;

  /// Gets the top current `[RouteRecorded]` object from the map.
  ///
  /// If there is only one route, returns the first.
  RouteRecorded? getCurrentRoute() {
    final List<RouteRecorded> routes = _routes.values
        .where((route) => route.rect != null)
        .toList(growable: false);

    if (routes.isEmpty) return null;

    if (routes.length == 1) return routes.first;

    return routes.last;
  }

  /// Handles a navigation event received from the `[SessionRecorderObserver]`.
  ///
  /// Validates that the session is initialized, otherwise throws
  /// a `[FlutterError]`.
  ///
  /// Processes the event according to the given `[NavigationType]` and updates
  /// the internal route registry accordingly.
  ///
  /// This method triggers the widget-tree capture through `_captureTreeHandler`.
  void handleRouting(
    Route<dynamic>? route,
    NavigationType type, {
    Route<dynamic>? oldRoute,
  }) {
    try {
      assert(() {
        if (!isSessionServiceInitialized) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary(
              'SessionRecorderObserver failed: SessionRecorder not initialized.',
            ),
            ErrorHint(
              'Ensure you pass the SessionRecorder.instance.init() to your app.',
            ),
            ErrorHint(
              'Example in main():\n'
              '  SessionRecorder.instance.init(params);\n',
            ),
            ErrorHint(
              'This call is blocking and will throw to surface the incorrect'
              'initialization order immediately.',
            ),
          ]);
        }

        return true;
      }());

      if (!isSessionServiceInitialized) return;

      isRouting = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        // TODO : verify again positions Routes?
        // TODO : remove every unmounted ?

        BuildContext? routeContext;
        String routeKey = "";
        final bool isValidRoute = _isValidRoute(route);

        if (isValidRoute) {
          routeContext = _findRouteContext(route!);
          routeKey = SerializeTreeUtils.createKeyRoute(route, routeContext);
        }

        BuildContext? oldRouteContext;
        String oldRouteKey = "";
        final bool isValidOldRoute = _isValidRoute(oldRoute);
        if (isValidOldRoute) {
          oldRouteContext = _findRouteContext(oldRoute!);
          oldRouteKey = SerializeTreeUtils.createKeyRoute(
            oldRoute,
            oldRouteContext,
          );
        }

        if (isValidRoute) {
          switch (type) {
            case NavigationType.push:
              final routeFound = _findRoute(routeKey, route!);
              if (routeFound != null) {
                _removeRoute(routeFound.value.key, routeFound.key);
              }

              _addRoute(routeKey, route, routeContext!);

              break;
            case NavigationType.remove:
              final routeFound = _findRoute(routeKey, route!);
              if (routeFound != null) {
                if (_lastNavigationType == NavigationType.push) {
                  _removeRoute(routeFound.value.key, routeFound.key);
                  break;
                }

                _removeRoutesAfter(routeFound.value.key, routeFound.key);
                break;
              }

              break;
            case NavigationType.pop:
              final routeFound = _findRoute(routeKey, route!);

              if (routeFound != null) {
                _removeRoutesAfter(routeFound.value.key, routeFound.key);
              }

              if (isValidOldRoute) {
                final routeFound = _findRoute(oldRouteKey, oldRoute!);
                if (routeFound != null) {
                  _addRoute(oldRouteKey, oldRoute, oldRouteContext!);
                }
              }

              break;
            case NavigationType.replace:
              if (isValidOldRoute) {
                final routeFound = _findRoute(oldRouteKey, oldRoute!);
                if (routeFound != null) {
                  _removeRoute(routeFound.value.key, routeFound.key);
                }

                _addRoute(routeKey, route!, routeContext!);
              }

              break;
            default:
              break;
          }
        }

        _lastNavigationType = type;

        final Route<dynamic>? currentRoute = (type == NavigationType.pop)
            ? (oldRoute != null && oldRoute.isCurrent)
                  ? oldRoute
                  : null
            : (route != null && route.isCurrent)
            ? route
            : null;

        if (currentRoute != null && (isValidRoute || isValidOldRoute)) {
          final ModalRoute routePage = currentRoute as ModalRoute;

          final Animation<double>? animation = routePage.animation;

          void capture(Duration duration) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _debounceRoute?.cancel();
              _debounceRoute = Timer(duration, () {
                _captureTreeHandler?.call();
              });
            });
          }

          if (animation == null ||
              animation.status == AnimationStatus.completed ||
              animation.value >= 0.999) {
            final Duration duration = routePage.transitionDuration;
            if (duration > Duration.zero) {
              capture(duration + Durations.short4);
            } else {
              capture(Durations.short3);
            }
            return;
          }

          void statusListener(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              animation.removeStatusListener(statusListener);

              capture(Durations.short1);
              return;
            }
          }

          animation.addStatusListener(statusListener);
        }
      });
    } catch (e, s) {
      SessionLogger.elog("!! >> [Some error]", e, s);
      return;
    }
  }

  /// Add the `route` into the `_routes` map.
  ///
  /// Creates a new `[RouteRecorded]` instances with some useful values.
  void _addRoute(
    String key,
    Route<dynamic> route,
    BuildContext subtreeContext,
  ) {
    final String routeName =
        route.settings.name ?? route.runtimeType.toString();
    final Rect? rect = _getRectFromContext(subtreeContext);

    final RouteRecorded routeRecorded = RouteRecorded(
      key: key,
      route: route,
      name: routeName,
      subtreeContext: subtreeContext,
      rect: rect,
    );

    _routes[route] = routeRecorded;
  }

  /// Removes the current `route` into the `_routes` map.
  void _removeRoute(String routeKey, Route<dynamic> route) {
    _routes.removeWhere(
      (key, value) => (value.key == routeKey || key == route),
    );
  }

  /// Removes all routes after find the current `route` into the `_routes` map.
  void _removeRoutesAfter(String routeKey, Route<dynamic> route) {
    bool isRouteFound = false;
    final List<MapEntry<Route<dynamic>, RouteRecorded>> routesToRemove = [];

    for (MapEntry<Route<dynamic>, RouteRecorded> entry
        in _routes.entries.toList()) {
      if (isRouteFound) {
        routesToRemove.add(entry);
      } else if ((entry.key == route || entry.value.key == routeKey)) {
        isRouteFound = true;
        routesToRemove.add(entry);
      }
    }

    for (MapEntry<Route<dynamic>, RouteRecorded> entry in routesToRemove) {
      _routes.remove(entry.key);
    }
  }

  /// Finds the current `route` into the `_routes` map.
  MapEntry<Route<dynamic>, RouteRecorded>? _findRoute(
    String key,
    Route<dynamic> route,
  ) => _routes.entries
      .cast<MapEntry<Route<dynamic>, RouteRecorded>?>()
      .firstWhere(
        (entry) => (entry!.key == route) || (entry.value.key == key),
        orElse: () => null,
      );

  /// Validates if the `route` is a `[ModalRoute]`.
  bool _isValidRoute(Route<dynamic>? route) {
    if (route == null) return false;

    try {
      if (route is ModalRoute) {
        return true;
      }

      if (route is OverlayRoute) {
        return false;
      }

      if (route.settings.name != null && route.settings.name!.isNotEmpty) {
        return false;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Finds the `[BuildContext]` from the `route`.
  BuildContext? _findRouteContext(Route<dynamic> route) {
    try {
      if (route is ModalRoute && route.subtreeContext != null) {
        final BuildContext? context = route.subtreeContext;
        if (context is Element && context.mounted) return context;
        if (context is BuildContext) return context;
      }

      final BuildContext? navigatorContext = route.navigator?.context;
      if (navigatorContext is Element && navigatorContext.mounted) {
        return navigatorContext;
      }
      if (navigatorContext is BuildContext) return navigatorContext;

      return null;
    } catch (e, s) {
      SessionLogger.elog("!! >> [Some error]", e, s);
      return null;
    }
  }

  /// Calculates and gets the `[Rect]` from the `context`;
  Rect? _getRectFromContext(BuildContext? context) {
    try {
      if (context == null) return null;

      final RenderObject? render = context.findRenderObject();
      if (render is RenderBox && render.attached && render.hasSize) {
        final Offset coordinates = render.localToGlobal(Offset.zero);
        return coordinates & render.size;
      }

      return null;
    } catch (e, s) {
      SessionLogger.elog("!! >> [Some error]", e, s);
      return null;
    }
  }
}
