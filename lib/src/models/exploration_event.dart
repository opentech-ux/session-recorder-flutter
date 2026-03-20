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

  String concatenateString();

  Map<String, dynamic> toMap();

  static ExplorationEvent fromMap(Map<String, dynamic> map) {
    final String typeName = (map['explorationType'] as String);

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
          endTimestamp: map['endTimestamp'] as int,
          viewport: rectViewport,
          positions: pos.map((p) => Offset(p["dx"], p["dy"])).toList(),
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

class DragExplorationEvent extends ExplorationEvent {
  final Offset position;

  const DragExplorationEvent({
    required super.timestamp,
    required super.viewport,
    required this.position,
  }) : super(explorationType: GesturesType.drag);

  @override
  String concatenateString() {
    final List<String> attrs = [
      timestamp.toString(),
      explorationType.name,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      '${position.dx.toInt()},${position.dy.toInt()}',
    ];

    return attrs.join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'explorationType': explorationType.name,
      'viewport': ExplorationEvent.rectToList(viewport),
      'position': ExplorationEvent.offsetToList(position),
    };
  }

  @override
  String toString() =>
      'DragExplorationEvent(timestamp: $timestamp, viewport: $viewport, position: $position)';
}

class PinchExplorationEvent extends ExplorationEvent {
  final int endTimestamp;
  final List<Offset> positions;

  const PinchExplorationEvent({
    required super.timestamp,
    required super.viewport,
    required this.endTimestamp,
    required this.positions,
  }) : super(explorationType: GesturesType.pinch);

  @override
  String concatenateString() {
    final String pos = positions
        .map((p) => '${p.dx.toInt()},${p.dy.toInt()}')
        .join('|');

    final List<String> attrs = [
      timestamp.toString(),
      explorationType.name,
      '${viewport.left.toInt()},${viewport.top.toInt()}',
      pos,
      endTimestamp.toString(),
    ];

    return attrs.join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'endTimestamp': endTimestamp,
      'explorationType': explorationType.name,
      'viewport': ExplorationEvent.rectToList(viewport),
      'positions': positions.map((o) => {'dx': o.dx, 'dy': o.dy}).toList(),
    };
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
    final String type = (phase == ScrollPhase.end)
        ? GesturesType.scrollEnd.name
        : GesturesType.scrollStart.name;

    final List<String> attrs = [
      timestamp.toString(),
      type,
      '${viewport.left.toInt()},${viewport.top.toInt()},${viewport.width.toInt()},${viewport.height.toInt()}',
    ];

    return attrs.join(':');
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'explorationType': explorationType.name,
      'viewport': ExplorationEvent.rectToList(viewport),
      'phase': phase.name,
    };
  }

  @override
  String toString() =>
      'ScrollExplorationEvent(timestamp: $timestamp, viewport: $viewport, phase: $phase)';
}
