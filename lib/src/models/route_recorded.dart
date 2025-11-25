import 'package:flutter/widgets.dart';

class RouteRecorded {
  final String key;
  final Route<dynamic> route;
  final String name;
  final BuildContext? subtreeContext;
  final Rect? rect;

  RouteRecorded({
    required this.key,
    required this.route,
    required this.name,
    required this.subtreeContext,
    required this.rect,
  });

  @override
  String toString() {
    return 'RouteRecorded(key: $key, route: $route, name: $name, subtreeContext: $subtreeContext, rect: $rect)';
  }
}
