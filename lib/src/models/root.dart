import 'dart:convert';

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

    return <String, dynamic>{
      'id': "z$id",
      't': widgetType,
      'b': b,
      'c': children.map((x) => x.toMap()).toList(),
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() => 'Root(id: $id, box: $box, children: ${children.length})';
}
