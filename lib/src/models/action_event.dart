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

  String concatenateString();

  Map<String, dynamic> toMap();

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

    switch (type) {
      case GesturesType.tap:
        return TapActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: Offset(
            (pos[0] as num).toDouble(),
            (pos[1] as num).toDouble(),
          ),
        );
      case GesturesType.longPress:
        return LongPressActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: Offset(
            (pos[0] as num).toDouble(),
            (pos[1] as num).toDouble(),
          ),
          duration: Duration(milliseconds: map['duration'] as int),
        );
      case GesturesType.doubleTap:
        return DoubleTapActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: Offset(
            (pos[0] as num).toDouble(),
            (pos[1] as num).toDouble(),
          ),
        );
      default:
        return TapActionEvent(
          timestampRelative: map['timestampRelative'] as int,
          zone: map['zone'] as String,
          viewport: rectViewport,
          position: Offset(
            (pos[0] as num).toDouble(),
            (pos[1] as num).toDouble(),
          ),
        );
    }
  }

  static List<double> rectToList(Rect r) =>
      [r.left, r.top, r.width, r.height].map((r) => r.toDouble()).toList();

  static List<double> offsetToList(Offset o) =>
      [o.dx, o.dy].map((o) => o.toDouble()).toList();
}

class TapActionEvent extends ActionEvent {
  const TapActionEvent({
    required super.timestampRelative,
    required super.zone,
    required super.viewport,
    required super.position,
  }) : super(actionType: GesturesType.tap);

  @override
  String concatenateString() {
    final List<String> attrs = [
      timestampRelative.toString(),
      actionType.name,
      zone,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      '${position.dx.toInt()},${position.dy.toInt()}',
    ];

    return attrs.join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timestampRelative': timestampRelative,
      'actionType': actionType.name,
      'zone': zone,
      'viewport': ActionEvent.rectToList(viewport),
      'position': ActionEvent.offsetToList(position),
    };
  }
}

class DoubleTapActionEvent extends ActionEvent {
  const DoubleTapActionEvent({
    required super.timestampRelative,
    required super.zone,
    required super.viewport,
    required super.position,
  }) : super(actionType: GesturesType.doubleTap);

  @override
  String concatenateString() {
    final List<String> attrs = [
      timestampRelative.toString(),
      actionType.name,
      zone,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      '${position.dx.toInt()},${position.dy.toInt()}',
    ];

    return attrs.join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timestampRelative': timestampRelative,
      'actionType': actionType.name,
      'zone': zone,
      'viewport': ActionEvent.rectToList(viewport),
      'position': ActionEvent.offsetToList(position),
    };
  }
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
    final List<String> attrs = [
      timestampRelative.toString(),
      actionType.name,
      zone,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      '${position.dx.toInt()},${position.dy.toInt()}',
      duration.inMilliseconds.toString(),
    ];

    return attrs.join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timestampRelative': timestampRelative,
      'actionType': actionType.name,
      'zone': zone,
      'viewport': ActionEvent.rectToList(viewport),
      'position': ActionEvent.offsetToList(position),
      'duration': duration.inMilliseconds,
    };
  }
}
