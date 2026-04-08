import 'package:flutter/material.dart';

import '../enums/gestures_type_enum.dart';

@immutable
abstract class ActionEvent {
  final int timestampRelative;
  final GesturesType actionType;
  final String zone;
  final Rect viewport;
  final Offset position;

  const ActionEvent({
    required this.timestampRelative,
    required this.zone,
    required this.actionType,
    required this.viewport,
    required this.position,
  });

  @mustCallSuper
  String concatenateString() {
    return [
      timestampRelative.toString(),
      actionType.name,
      zone,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      '${position.dx.toInt()},${position.dy.toInt()}',
    ].join(':');
  }

  @mustCallSuper
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timestampRelative': timestampRelative,
      'actionType': actionType.name,
      'zone': zone,
      'viewport': [
        viewport.left,
        viewport.top,
        viewport.width,
        viewport.height,
      ],
      'position': [position.dx, position.dy],
    };
  }

  static ActionEvent fromMap(Map<String, dynamic> map) {
    final String typeName = map['actionType'] as String;

    final GesturesType type = GesturesType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => GesturesType.tap,
    );

    final List<dynamic> viewport = map['viewport'] as List<dynamic>;
    final Rect rectViewport = Rect.fromLTWH(
      (viewport[0] as num).toDouble(),
      (viewport[1] as num).toDouble(),
      (viewport[2] as num).toDouble(),
      (viewport[3] as num).toDouble(),
    );

    final List<dynamic> pos = map['position'] as List<dynamic>;
    final Offset offsetPosition = Offset(pos[0] as double, pos[1] as double);

    switch (type) {
      case GesturesType.longPress:
        return LongPressActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: offsetPosition,
          duration: Duration(milliseconds: map['duration'] as int),
        );
      case GesturesType.doubleTap:
        return DoubleTapActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: offsetPosition,
        );
      case GesturesType.tap:
      default:
        return TapActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: offsetPosition,
        );
    }
  }
}

class TapActionEvent extends ActionEvent {
  const TapActionEvent({
    required super.timestampRelative,
    required super.zone,
    required super.viewport,
    required super.position,
  }) : super(actionType: GesturesType.tap);
}

class DoubleTapActionEvent extends ActionEvent {
  const DoubleTapActionEvent({
    required super.timestampRelative,
    required super.zone,
    required super.viewport,
    required super.position,
  }) : super(actionType: GesturesType.doubleTap);
}

class LongPressActionEvent extends ActionEvent {
  final Duration duration;

  const LongPressActionEvent({
    required super.timestampRelative,
    required super.zone,
    required super.viewport,
    required super.position,
    required this.duration,
  }) : super(actionType: GesturesType.longPress);

  @override
  String concatenateString() {
    return '${super.concatenateString()}:${duration.inMilliseconds}';
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map['duration'] = duration.inMilliseconds;
    return map;
  }
}
