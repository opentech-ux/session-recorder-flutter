import 'dart:convert';

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
    actionsEvents.add(actionEvent);
  }

  String toJson() => json.encode(toMap());

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lib_v': libraryVersion,
      'framework': 'Flutter',
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
