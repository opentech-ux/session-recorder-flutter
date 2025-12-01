import 'dart:convert';

import 'package:flutter/material.dart';

class Root {
  final int id;
  final int objectId;
  final int parentId;
  final String widgetType;
  final String renderType;
  final Rect box;
  final List<Root> children;

  Root({
    required this.id,
    required this.objectId,
    required this.parentId,
    required this.widgetType,
    required this.renderType,
    required this.box,
    required this.children,
  });

  Root copyWith({
    int? id,
    int? objectId,
    int? parentId,
    String? widgetType,
    String? renderType,
    Rect? box,
    List<Root>? children,
  }) {
    return Root(
      id: id ?? this.id,
      objectId: objectId ?? this.objectId,
      parentId: parentId ?? this.parentId,
      widgetType: widgetType ?? this.widgetType,
      renderType: renderType ?? this.renderType,
      box: box ?? this.box,
      children: children ?? this.children,
    );
  }

  Map<String, dynamic> toMap() {
    final List<int> b = [
      box.left.toInt(),
      box.top.toInt(),
      box.width.toInt(),
      box.height.toInt(),
    ];

    return <String, dynamic>{
      'id': "z$id",
      'b': b,
      'c': children.map((x) => x.toMap()).toList(),
    };
  }

  Map<String, dynamic> toMapIsolate() {
    final rect = [box.left, box.top, box.width, box.height];
    return <String, dynamic>{
      'id': id,
      'objectId': objectId,
      'parentId': parentId,
      'widgetType': widgetType,
      'renderType': renderType,
      'box': rect,
      'children': children.map((x) => x.toMapIsolate()).toList(),
    };
  }

  factory Root.fromMap(Map<String, dynamic> map) {
    final List<double> b = (map['box'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    return Root(
      id: map['id'] as int,
      objectId: map['objectId'] as int,
      parentId: map['parentId'] as int,
      widgetType: map['widgetType'] as String,
      renderType: map['renderType'] as String,
      box: Rect.fromLTWH(b[0], b[1], b[2], b[3]),
      children: List<Root>.from(
        map['children'].map<Root>(
          (x) => Root.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  String toJsonIsolate() => json.encode(toMapIsolate());

  factory Root.fromJson(String source) =>
      Root.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'Root(id: $id, objectId: $objectId, parentId: $parentId, widgetType: $widgetType, renderType: $renderType, box: $box, children: $children)';

  @override
  bool operator ==(covariant Root other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.objectId == objectId &&
        other.parentId == parentId &&
        other.widgetType == widgetType &&
        other.renderType == renderType &&
        other.box == box &&
        other.children == children;
  }

  @override
  int get hashCode => id.hashCode ^ box.hashCode;
}
