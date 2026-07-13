// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import 'models.dart';

@immutable
abstract class LomAbstract {
  final String id;
  final int timestamp;
  final Root? root;
  final Offset? viewportOffset;

  const LomAbstract({
    required this.id,
    required this.timestamp,
    this.root,
    this.viewportOffset,
  });

  List<int>? get serializedViewportOffset => viewportOffset == null
      ? null
      : [viewportOffset!.dx.round(), viewportOffset!.dy.round()];

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
    super.viewportOffset,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'ts': timestamp,
      'w': width,
      'h': height,
      'r': (root == null) ? "" : root?.toMap(),
    };

    if (serializedViewportOffset case final viewport?) {
      map['v'] = viewport;
    }

    return map;
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'Lom(id: $id, timestamp: $timestamp, width: $width, height: $height, viewportOffset: $viewportOffset, root: $root)';
  }
}

class LomRef extends LomAbstract {
  const LomRef({
    required super.id,
    required super.timestamp,
    super.root,
    super.viewportOffset,
  });

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'ref': id, 'ts': timestamp};

    if (serializedViewportOffset case final viewport?) {
      map['v'] = viewport;
    }

    return map;
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() =>
      'LomRef(id: $id, timestamp: $timestamp, viewportOffset: $viewportOffset)';
}

@internal
class LocalLomRef extends LomRef {
  /// Internal ref used only to refresh the current LOM without network noise.
  const LocalLomRef({
    required super.id,
    required super.timestamp,
    required super.root,
    super.viewportOffset,
  });
}
