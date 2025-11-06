// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'models.dart';

abstract class LomAbstract {
  final String id;
  final int timestamp;

  LomAbstract({
    required this.id,
    required this.timestamp,
  });

  Map<String, dynamic> toMap();
}

class Lom extends LomAbstract {
  final int width;
  final int height;
  final Root? root;

  Lom({
    required super.id,
    required super.timestamp,
    required this.width,
    required this.height,
    this.root,
  });

  Lom copyWith({
    String? id,
    int? timestamp,
    int? width,
    int? height,
    Root? root,
  }) {
    return Lom(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      width: width ?? this.width,
      height: height ?? this.height,
      root: root ?? this.root,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'ts': timestamp,
      'w': width,
      'h': height,
      'r': (root == null) ? "" : root?.toMap(),
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'Lom(id: $id, timestamp: $timestamp, width: $width, height: $height, root: $root)';
  }

  @override
  bool operator ==(covariant Lom other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.timestamp == timestamp &&
        other.width == width &&
        other.height == height &&
        other.root == root;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        timestamp.hashCode ^
        width.hashCode ^
        height.hashCode ^
        root.hashCode;
  }
}

class LomRef extends LomAbstract {
  LomRef({
    required super.id,
    required super.timestamp,
  });

  LomRef copyWith({
    String? id,
    int? timestamp,
  }) {
    return LomRef(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'ref': id,
      'ts': timestamp,
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() => 'LomRef(id: $id, timestamp: $timestamp)';

  @override
  bool operator ==(covariant LomRef other) {
    if (identical(this, other)) return true;

    return other.id == id && other.timestamp == timestamp;
  }

  @override
  int get hashCode => id.hashCode ^ timestamp.hashCode;
}
