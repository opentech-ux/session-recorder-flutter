import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class Root {
  final int id;
  final String objectId;
  final String widgetType;
  final String renderType;
  final Rect box;
  final List<Root> children;

  const Root({
    required this.id,
    required this.objectId,
    required this.widgetType,
    required this.renderType,
    required this.box,
    required this.children,
  });

  Map<String, dynamic> toMap() {
    final List<int> b = [
      box.left.toInt(),
      box.top.toInt(),
      box.width.toInt(),
      box.height.toInt(),
    ];

    final map = <String, dynamic>{
      'id': "z$id",
      'b': b,
      'c': children.map((x) => x.toMap()).toList(),
    };

    if (kDebugMode) {
      map['t'] = widgetType;
      map['rt'] = renderType;
      map['oid'] = objectId;
      map['widget'] = widgetType;
      map['render'] = renderType;
      map['object'] = objectId;
    }

    return map;
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() => 'Root(id: $id, box: $box, children: ${children.length})';
}
