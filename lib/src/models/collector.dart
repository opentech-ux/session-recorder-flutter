import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';

class PointerTrace {
  final int pointer;
  final List<TimedPosition> positions;
  GesturesType type;
  // Timer? timer;

  PointerTrace({
    required this.pointer,
    List<TimedPosition>? positions,
    required this.type,
    // Timer? timer,
  }) : positions = positions ?? [];

  TimedPosition get first => positions.isNotEmpty
      ? positions.first
      : TimedPosition(Offset.zero, viewport: Rect.zero);
  TimedPosition get last => positions.isNotEmpty
      ? positions.last
      : TimedPosition(Offset.zero, viewport: Rect.zero);

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

  // void dispose() {
  //   timer?.cancel();
  // }

  void setType(GesturesType type) {
    this.type = type;
  }

  void add(Offset position, {required Rect viewport}) {
    positions.add(TimedPosition(position, viewport: viewport));
  }

  void clear() {
    positions.clear();
  }

  @override
  String toString() =>
      'PointerTrace(pointer: $pointer, positions: $positions, type: $type)';
}

class TimedPosition {
  final int timestamp;
  final Offset position;
  final Rect viewport;

  TimedPosition(this.position, {required this.viewport})
    : timestamp = DateTime.now().millisecondsSinceEpoch;

  @override
  String toString() =>
      'TimedPosition(timestamp: $timestamp, position: $position, viewport: $viewport)';
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
