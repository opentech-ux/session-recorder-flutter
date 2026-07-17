import 'package:flutter/material.dart';

import '../enums/gestures_type_enum.dart';

@immutable
abstract class ExplorationEvent {
  final int timestamp;
  final Rect viewport;
  final GesturesType explorationType;
  final String lomRef;

  const ExplorationEvent({
    required this.timestamp,
    required this.viewport,
    required this.explorationType,
    required this.lomRef,
  });

  @protected
  String get viewportStringLT =>
      '${viewport.left.toInt()},${viewport.top.toInt()}';

  @protected
  String get viewportStringLTWH =>
      '${viewport.left.toInt()},${viewport.top.toInt()},${viewport.width.toInt()},${viewport.height.toInt()}';

  String concatenateString();
}

class DragExplorationEvent extends ExplorationEvent {
  final Offset position;
  final int pointer;

  const DragExplorationEvent({
    required super.timestamp,
    required this.pointer,
    required super.viewport,
    required this.position,
    required super.lomRef,
  }) : super(explorationType: GesturesType.drag);

  @override
  String concatenateString() {
    return [
      timestamp.toString(),
      explorationType.name,
      pointer,
      viewportStringLT,
      '${position.dx.toInt()},${position.dy.toInt()}',
      lomRef,
    ].join(':');
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
    required super.lomRef,
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
      lomRef,
    ].join(':');
  }

  @override
  String toString() =>
      'PinchExplorationEvent(timestamp: $timestamp, endTimestamp: $endTimestamp, viewport: $viewport, positions: $positions)';
}

class ScrollExplorationEvent extends ExplorationEvent {
  final ScrollPhase phase;
  final Offset offset;

  const ScrollExplorationEvent({
    required super.timestamp,
    required super.viewport,
    required this.phase,
    required this.offset,
    required super.lomRef,
  }) : super(explorationType: GesturesType.scroll);

  @override
  String concatenateString() {
    final String typeName = (phase == ScrollPhase.end)
        ? GesturesType.scrollEnd.name
        : GesturesType.scrollStart.name;

    return [
      timestamp.toString(),
      typeName,
      viewportStringLTWH,
      '${offset.dx.toInt()},${offset.dy.toInt()}',
      lomRef,
    ].join(':');
  }

  @override
  String toString() =>
      'ScrollExplorationEvent(timestamp: $timestamp, viewport: $viewport, offset: $offset, phase: $phase)';
}
