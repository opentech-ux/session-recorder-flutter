import 'package:flutter/material.dart';

import '../enums/gestures_type_enum.dart';

@immutable
abstract class ActionEvent {
  final int timestampRelative;
  final GesturesType actionType;
  final Rect viewport;
  final Offset position;
  final String lomRef;

  const ActionEvent({
    required this.timestampRelative,
    required this.actionType,
    required this.viewport,
    required this.position,
    required this.lomRef,
  });

  @protected
  List<String> get baseParts => [
    timestampRelative.toString(),
    actionType.name,
    '${viewport.left.toInt()},${viewport.top.toInt()}',
    '${position.dx.toInt()},${position.dy.toInt()}',
  ];

  String concatenateString() {
    return [...baseParts, lomRef].join(':');
  }
}

class TapActionEvent extends ActionEvent {
  const TapActionEvent({
    required super.timestampRelative,
    required super.viewport,
    required super.position,
    required super.lomRef,
  }) : super(actionType: GesturesType.tap);
}

class DoubleTapActionEvent extends ActionEvent {
  /// Internal origin used only to keep tap/doubleTap ordering coherent.
  final int? originTimestampRelative;
  final Offset? originPosition;

  const DoubleTapActionEvent({
    required super.timestampRelative,
    required super.viewport,
    required super.position,
    required super.lomRef,
    this.originTimestampRelative,
    this.originPosition,
  }) : super(actionType: GesturesType.doubleTap);
}

class LongPressActionEvent extends ActionEvent {
  final Duration duration;

  const LongPressActionEvent({
    required super.timestampRelative,
    required super.viewport,
    required super.position,
    required super.lomRef,
    required this.duration,
  }) : super(actionType: GesturesType.longPress);

  @override
  String concatenateString() {
    return [...baseParts, duration.inMilliseconds.toString(), lomRef].join(':');
  }
}
