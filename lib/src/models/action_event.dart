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
}
