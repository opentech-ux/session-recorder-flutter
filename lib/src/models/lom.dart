// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:meta/meta.dart';

import 'models.dart';

@immutable
abstract class LomAbstract {
  final String id;
  final int timestamp;
  final Root? root;

  const LomAbstract({required this.id, required this.timestamp, this.root});

  Map<String, dynamic> toMap();
}

class Lom extends LomAbstract {
  final int width;
  final int height;

  const Lom({
    required super.id,
    required super.timestamp,
    required this.width,
    required this.height,
    super.root,
  });

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
}

class LomRef extends LomAbstract {
  const LomRef({required super.id, required super.timestamp, super.root});

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{'ref': id, 'ts': timestamp};
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() => 'LomRef(id: $id, timestamp: $timestamp)';
}
