import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';

class PointerTrace {
  final int pointer;
  final List<TimedPosition> positions;
  GesturesType type;
  final bool isOrphanedPointer;

  PointerTrace({
    required this.pointer,
    List<TimedPosition>? positions,
    required this.type,
    this.isOrphanedPointer = false,
  }) : positions = positions ?? [];

  /// Requires this trace to contain at least one real position.
  TimedPosition get first => positions.first;

  /// Requires this trace to contain at least one real position.
  TimedPosition get last => positions.last;

  Offset get firstPosition => first.position;
  Offset get lastPosition => last.position;

  int get firstTimestamp => first.timestamp;
  int get lastTimestamp => last.timestamp;

  bool get isEmpty => positions.isEmpty;
  int get length => positions.length;

  Duration get duration {
    if (positions.isEmpty) return Duration.zero;
    if (positions.length < 2) {
      return Duration(
        milliseconds: DateTime.now().millisecondsSinceEpoch - firstTimestamp,
      );
    }

    return Duration(milliseconds: lastTimestamp - firstTimestamp);
  }

  double get distance =>
      isEmpty ? 0.0 : (lastPosition - firstPosition).distance;

  void setType(GesturesType type) {
    this.type = type;
  }

  void add(Offset position, {required Rect viewport, String lomRef = ''}) {
    positions.add(
      TimedPosition(position, viewport: viewport, lomRef: lomRef),
    );
  }

  void clear() {
    positions.clear();
  }

  PointerTrace splitForTransition({
    required GesturesType newType,
    bool isOrphanedPointer = false,
  }) {
    return PointerTrace(
      pointer: pointer,
      type: newType,
      isOrphanedPointer: isOrphanedPointer,
    )..add(
        lastPosition,
        viewport: positions.last.viewport,
        lomRef: positions.last.lomRef,
      );
  }

  @override
  String toString() =>
      'PointerTrace(pointer: $pointer, positions: $positions, type: $type)';
}

class TimedPosition {
  final int timestamp;
  final Offset position;
  final Rect viewport;
  final String lomRef;

  TimedPosition(this.position, {required this.viewport, this.lomRef = ''})
    : timestamp = DateTime.now().millisecondsSinceEpoch;

  @override
  String toString() =>
      'TimedPosition(timestamp: $timestamp, position: $position, viewport: $viewport, lomRef: $lomRef)';
}

@immutable
class ViewportPosition {
  final int timestamp;
  final Rect viewport;

  const ViewportPosition(this.timestamp, this.viewport);

  @override
  String toString() =>
      'ViewportPosition(timestamp: $timestamp, viewport: $viewport)';
}

class ScrollSession {
  final String id;
  final List<double> positions;

  ScrollSession({required double startPixel})
    : id = DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      positions = [startPixel];
}
