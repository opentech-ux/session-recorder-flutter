import 'dart:convert';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/constants/version_constant.dart';

import 'models.dart';

class Chunk {
  String sId;

  final int timestamp;
  final List<LomAbstract> loms;
  final List<ExplorationEvent> explorationEvents;
  final List<ActionEvent> actionsEvents;

  Chunk()
    : timestamp = DateTime.now().millisecondsSinceEpoch,
      sId = "",
      actionsEvents = [],
      explorationEvents = [],
      loms = [];

  bool get isChunkEmpty =>
      loms.isEmpty && explorationEvents.isEmpty && actionsEvents.isEmpty;

  /// Add a [LomAbstract] to the [Chunk].
  ///
  /// Could be a [Lom] or [LomRef] classes.
  void addLom(LomAbstract lom) {
    loms.add(lom);
  }

  /// Add a [ExplorationEvent] list to the [Chunk]
  void addExplorationEvent(ExplorationEvent exploration) {
    explorationEvents.add(exploration);
  }

  /// Add a [ActionEvent] to the [Chunk]
  void addActionEvent(ActionEvent actionEvent) {
    if (actionEvent is DoubleTapActionEvent) {
      final tapIndex = _findDoubleTapOrigin(actionEvent);
      if (tapIndex != null) {
        actionsEvents.insert(tapIndex + 1, actionEvent);
        return;
      }
    }

    actionsEvents.add(actionEvent);
  }

  /// Finds the tap that originated a double tap, when it is still in this chunk.
  int? _findDoubleTapOrigin(DoubleTapActionEvent doubleTap) {
    final originTimestamp = doubleTap.originTimestampRelative;
    if (originTimestamp != null) {
      final originPosition = doubleTap.originPosition;
      for (var i = actionsEvents.length - 1; i >= 0; i--) {
        final action = actionsEvents[i];
        if (action is TapActionEvent &&
            action.timestampRelative == originTimestamp &&
            (originPosition == null || action.position == originPosition)) {
          return i;
        }
      }
    }

    int? index;
    double? bestDistance;

    for (var i = 0; i < actionsEvents.length; i++) {
      final action = actionsEvents[i];
      if (action is! TapActionEvent) continue;
      if (action.zone != doubleTap.zone) continue;

      final elapsed = doubleTap.timestampRelative - action.timestampRelative;
      if (elapsed < 0 || elapsed > doubleTapTimeout.inMilliseconds) continue;

      final distance = (doubleTap.position - action.position).distance;
      if (distance > doubleTapSlop) continue;

      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        index = i;
      }
    }

    return index;
  }

  String toJson() => json.encode(toMap());

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lib_v': libraryVersion,
      'type': libraryType,
      'ts': timestamp,
      'sid': sId,
      'loms': loms.map((x) => x.toMap()).toList(),
      'pnt': [],
      'ee': explorationEvents.map((x) => x.concatenateString()).toList(),
      'ae': actionsEvents.map((x) => x.concatenateString()).toList(),
    };
  }

  @override
  String toString() {
    return 'Chunk('
        'lib_v: $libraryVersion, '
        'lib_t: $libraryType, '
        'timestamp: $timestamp, '
        'sId: $sId,'
        'loms: $loms, '
        'explorationEvents: $explorationEvents, '
        'actionsEvents: $actionsEvents, '
        ')';
  }
}
