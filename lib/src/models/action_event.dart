import 'package:flutter/material.dart';

import '../enums/gestures_type_enum.dart';

@immutable
abstract class ActionEvent {
  final int timestampRelative;
  final GesturesType actionType;
  final Rect viewport;
  final String lomRef;

  const ActionEvent({
    required this.timestampRelative,
    required this.actionType,
    required this.viewport,
    required this.lomRef,
  });

  Offset get position;

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
  @override
  final Offset position;

  const TapActionEvent({
    required super.timestampRelative,
    required super.viewport,
    required this.position,
    required super.lomRef,
  }) : super(actionType: GesturesType.tap);
}

class DoubleTapActionEvent extends ActionEvent {
  final int secondTimestamp;
  final List<Offset> positions;

  DoubleTapActionEvent({
    required super.timestampRelative,
    required super.viewport,
    required this.secondTimestamp,
    required List<Offset> positions,
    required super.lomRef,
  }) : assert(positions.length == 2),
       positions = List<Offset>.unmodifiable(positions),
       super(actionType: GesturesType.doubleTap);

  @override
  Offset get position => positions.first;

  @override
  String concatenateString() {
    final positionsString = positions
        .map((position) => '${position.dx.toInt()},${position.dy.toInt()}')
        .join('|');

    return [
      timestampRelative.toString(),
      actionType.name,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      positionsString,
      secondTimestamp.toString(),
      lomRef,
    ].join(':');
  }
}

class LongPressActionEvent extends ActionEvent {
  @override
  final Offset position;
  final Duration duration;

  const LongPressActionEvent({
    required super.timestampRelative,
    required super.viewport,
    required this.position,
    required super.lomRef,
    required this.duration,
  }) : super(actionType: GesturesType.longPress);

  @override
  String concatenateString() {
    return [...baseParts, duration.inMilliseconds.toString(), lomRef].join(':');
  }
}
