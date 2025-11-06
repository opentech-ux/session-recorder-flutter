import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';

class Chunk {
  final String libraryVersion;
  final int timestamp;
  final String sId;
  final List<LomAbstract> loms;
  final List<ExplorationEvent> explorationEvents;
  final List<ActionEvent> actionsEvents;

  Chunk({
    required this.libraryVersion,
    required this.timestamp,
    required this.sId,
    required this.loms,
    required this.explorationEvents,
    required this.actionsEvents,
  });

  Chunk copyWith({
    String? libraryVersion,
    int? timestamp,
    String? sId,
    List<LomAbstract>? loms,
    List<ExplorationEvent>? explorationEvents,
    List<ActionEvent>? actionsEvents,
  }) {
    return Chunk(
      libraryVersion: libraryVersion ?? this.libraryVersion,
      timestamp: timestamp ?? this.timestamp,
      sId: sId ?? this.sId,
      loms: loms ?? this.loms,
      explorationEvents: explorationEvents ?? this.explorationEvents,
      actionsEvents: actionsEvents ?? this.actionsEvents,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lib_v': libraryVersion,
      'ts': timestamp,
      'sid': sId,
      'loms': loms.map((x) => x.toMap()).toList(),
      'pnt': [],
      'ee': explorationEvents.map((x) => x.concatenateString()).toList(),
      'ae': actionsEvents.map((x) => x.concatenateString()).toList(),
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'Chunk('
        'libraryVersion: $libraryVersion, '
        'timestamp: $timestamp, '
        'sId: $sId,'
        'loms: $loms, '
        'explorationEvents: $explorationEvents, '
        'actionsEvents: $actionsEvents, '
        ')';
  }

  @override
  bool operator ==(covariant Chunk other) {
    if (identical(this, other)) return true;

    return other.libraryVersion == libraryVersion &&
        other.timestamp == timestamp &&
        other.sId == sId &&
        listEquals(other.loms, loms) &&
        listEquals(other.explorationEvents, explorationEvents) &&
        listEquals(other.actionsEvents, actionsEvents);
  }

  @override
  int get hashCode {
    return libraryVersion.hashCode ^
        timestamp.hashCode ^
        sId.hashCode ^
        loms.hashCode ^
        explorationEvents.hashCode ^
        actionsEvents.hashCode;
  }
}
