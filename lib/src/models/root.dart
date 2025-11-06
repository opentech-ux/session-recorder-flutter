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

  factory Root.fromMap(Map<String, dynamic> map) {
    final List<int> b = map["b"] as List<int>;

    return Root(
      id: map['id'] as int,
      objectId: map['objectId'] as int,
      parentId: map['parentId'] as int,
      widgetType: map['widgetType'] as String,
      renderType: map['renderType'] as String,
      box: Rect.fromLTWH(
        b[0].toDouble(),
        b[1].toDouble(),
        b[2].toDouble(),
        b[3].toDouble(),
      ),
      children: List<Root>.from(
        map['children'].map<Root>(
          (x) => Root.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

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
