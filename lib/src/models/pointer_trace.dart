// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_record_ux/src/enums/gestures_type_enum.dart';

class PointerTrace {
  final int pointer;
  final List<TimedPosition> positions;
  GesturesType type;
  Timer? timer;

  PointerTrace({
    required this.pointer,
    List<TimedPosition>? positions,
    required this.type,
    Timer? timer,
  }) : positions = positions ?? [];

  TimedPosition? get first => positions.isNotEmpty ? positions.first : null;
  TimedPosition? get last => positions.isNotEmpty ? positions.last : null;

  Offset? get firstPosition => first?.position;
  Offset? get lastPosition => last?.position;

  int? get firstTimestamp => first?.timestamp;
  int? get lastTimestamp => last?.timestamp;

  bool get isEmpty => positions.isEmpty;
  int get length => positions.length;

  Duration get duration {
    if (positions.isEmpty) return Duration.zero;
    if (positions.length < 2) {
      return Duration(
        milliseconds: DateTime.now().millisecondsSinceEpoch - firstTimestamp!,
      );
    }

    return Duration(milliseconds: lastTimestamp! - firstTimestamp!);
  }

  double get distance =>
      isEmpty ? 0.0 : (lastPosition! - firstPosition!).distance;

  void dispose() {
    timer?.cancel();
  }

  void setType(GesturesType type) {
    this.type = type;
  }

  void add(Offset position, int timestamp) {
    positions.add(TimedPosition(timestamp, position));
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

  TimedPosition(this.timestamp, this.position);

  @override
  String toString() =>
      'TimedPosition(timestamp: $timestamp, position: $position)';
}

class ViewportPosition {
  final int timestamp;
  final Rect viewport;

  ViewportPosition(this.timestamp, this.viewport);

  @override
  String toString() =>
      'ViewportPosition(timestamp: $timestamp, viewport: $viewport)';
}
