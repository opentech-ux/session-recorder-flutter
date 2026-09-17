import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';

class PointerTrace {
  final int pointer;
  final String lomRef;
  final bool isLomStateResolved;
  final int downOrder;
  final List<TimedPosition> positions;
  GesturesType type;

  /// This transition trace may be a drag, but never a tap or long press.
  final bool isPostTransitionDragOnly;

  PointerTrace({
    required this.pointer,
    this.lomRef = '',
    this.isLomStateResolved = false,
    this.downOrder = 0,
    List<TimedPosition>? positions,
    required this.type,
    this.isPostTransitionDragOnly = false,
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

  void add(Offset position, {required Rect viewport}) {
    positions.add(
      TimedPosition(position, viewport: viewport, lomRef: lomRef),
    );
  }

  PointerTrace splitForTransition({
    required GesturesType newType,
    bool isPostTransitionDragOnly = false,
  }) {
    return PointerTrace(
      pointer: pointer,
      lomRef: lomRef,
      isLomStateResolved: isLomStateResolved,
      downOrder: downOrder,
      type: newType,
      isPostTransitionDragOnly: isPostTransitionDragOnly,
    )..add(
        lastPosition,
        viewport: positions.last.viewport,
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
