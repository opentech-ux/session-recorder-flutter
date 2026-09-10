// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:meta/meta.dart';

import 'models.dart';

@immutable
abstract class LomAbstract {
  final String ref;
  final int timestamp;
  final Root? root;

  const LomAbstract({required this.ref, required this.timestamp, this.root});

  Map<String, dynamic> toMap();
}

class Lom extends LomAbstract {
  final String id;
  final int width;
  final int height;

  const Lom({
    required this.id,
    required super.ref,
    required super.timestamp,
    required this.width,
    required this.height,
    super.root,
  });

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'ref': ref,
      'ts': timestamp,
      'w': width,
      'h': height,
      'r': (root == null) ? "" : root?.toMap(),
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'Lom(id: $id, ref: $ref, timestamp: $timestamp, width: $width, height: $height, root: $root)';
  }
}

class LomRef extends LomAbstract {
  const LomRef({required super.ref, required super.timestamp, super.root});

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{'ref': ref, 'ts': timestamp};
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() => 'LomRef(ref: $ref, timestamp: $timestamp)';
}

@internal
class LocalLomRef extends LomRef {
  /// Internal ref used only to refresh the current LOM without network noise.
  const LocalLomRef({
    required super.ref,
    required super.timestamp,
    required super.root,
  });
}
