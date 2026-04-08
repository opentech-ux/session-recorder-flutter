import 'package:flutter/material.dart';

import '../enums/gestures_type_enum.dart';

@immutable
abstract class ExplorationEvent {
  final int timestamp;
  final Rect viewport;
  final GesturesType explorationType;

  const ExplorationEvent({
    required this.timestamp,
    required this.viewport,
    required this.explorationType,
  });

  @protected
  String get viewportStringLT =>
      '${viewport.left.toInt()},${viewport.top.toInt()}';

  @protected
  String get viewportStringLTWH =>
      '${viewport.left.toInt()},${viewport.top.toInt()},${viewport.width.toInt()},${viewport.height.toInt()}';

  String concatenateString();

  @mustCallSuper
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timestamp': timestamp,
      'explorationType': explorationType.name,
      'viewport': [
        viewport.left,
        viewport.top,
        viewport.width,
        viewport.height,
      ],
    };
  }

  static ExplorationEvent fromMap(Map<String, dynamic> map) {
    final String typeName = map['explorationType'] as String;

    final GesturesType type = GesturesType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => GesturesType.drag,
    );

    final List<dynamic> viewport = map['viewport'] as List<dynamic>;
    final Rect rectViewport = Rect.fromLTWH(
      (viewport[0] as num).toDouble(),
      (viewport[1] as num).toDouble(),
      (viewport[2] as num).toDouble(),
      (viewport[3] as num).toDouble(),
    );

    switch (type) {
      case GesturesType.pinch:
        final List<dynamic> pos = map['positions'] as List<dynamic>;
        return PinchExplorationEvent(
          timestamp: map['timestamp'] as int,
          pointer: map['pointer'] as int,
          endTimestamp: map['endTimestamp'] as int,
          viewport: rectViewport,
          positions: pos
              .map(
                (p) => Offset(
                  (p['dx'] as num).toDouble(),
                  (p['dy'] as num).toDouble(),
                ),
              )
              .toList(),
        );

      case GesturesType.scroll:
        final String phaseName = map['phase'] as String;
        final ScrollPhase phase = ScrollPhase.values.firstWhere(
          (p) => p.name == phaseName,
          orElse: () => ScrollPhase.update,
        );
        return ScrollExplorationEvent(
          timestamp: map['timestamp'] as int,
          viewport: rectViewport,
          phase: phase,
        );

      case GesturesType.drag:
      default:
        final List<dynamic> pos = map['position'] as List<dynamic>;
        return DragExplorationEvent(
          timestamp: map['timestamp'] as int,
          pointer: map['pointer'] as int,

          viewport: rectViewport,
          position: Offset(
            (pos[0] as num).toDouble(),
            (pos[1] as num).toDouble(),
          ),
        );
    }
  }
}

class DragExplorationEvent extends ExplorationEvent {
  final Offset position;
  final int pointer;

  const DragExplorationEvent({
    required super.timestamp,
    required this.pointer,
    required super.viewport,
    required this.position,
  }) : super(explorationType: GesturesType.drag);

  @override
  String concatenateString() {
    return [
      timestamp.toString(),
      explorationType.name,
      pointer,
      viewportStringLT,
      '${position.dx.toInt()},${position.dy.toInt()}',
    ].join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()..addAll({
      'pointer': pointer,
      'position': [position.dx, position.dy],
    });
  }

  @override
  String toString() =>
      'DragExplorationEvent(timestamp: $timestamp, viewport: $viewport, position: $position)';
}

class PinchExplorationEvent extends ExplorationEvent {
  final int endTimestamp;
  final int pointer;
  final List<Offset> positions;

  const PinchExplorationEvent({
    required super.timestamp,
    required this.pointer,
    required super.viewport,
    required this.endTimestamp,
    required this.positions,
  }) : super(explorationType: GesturesType.pinch);

  @override
  String concatenateString() {
    final String positionsString = positions
        .map((p) => '${p.dx.toInt()},${p.dy.toInt()}')
        .join('|');
    return [
      timestamp.toString(),
      explorationType.name,
      pointer,
      viewportStringLT,
      positionsString,
      endTimestamp.toString(),
    ].join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()..addAll({
      'pointer': pointer,
      'endTimestamp': endTimestamp,
      'positions': positions.map((o) => {'dx': o.dx, 'dy': o.dy}).toList(),
    });
  }

  @override
  String toString() =>
      'PinchExplorationEvent(timestamp: $timestamp, endTimestamp: $endTimestamp, viewport: $viewport, positions: $positions)';
}

class ScrollExplorationEvent extends ExplorationEvent {
  final ScrollPhase phase;

  const ScrollExplorationEvent({
    required super.timestamp,
    required super.viewport,
    required this.phase,
  }) : super(explorationType: GesturesType.scroll);

  @override
  String concatenateString() {
    final String typeName = (phase == ScrollPhase.end)
        ? GesturesType.scrollEnd.name
        : GesturesType.scrollStart.name;

    return [timestamp.toString(), typeName, viewportStringLTWH].join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return super.toMap()..addAll({'phase': phase.name});
  }

  @override
  String toString() =>
      'ScrollExplorationEvent(timestamp: $timestamp, viewport: $viewport, phase: $phase)';
}
