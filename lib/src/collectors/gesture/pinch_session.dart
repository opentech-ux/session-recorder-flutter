import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/collectors/gesture/gesture_sampling.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

final class PinchSession {
  final int startTimestamp;
  final Rect viewport;
  final String lomRef;
  final bool isLomStateResolved;

  final List<_PinchTrackState> _tracks = [];
  final Map<int, _PinchTrackState> _activeTracks = {};

  PinchSession({
    required this.startTimestamp,
    required this.viewport,
    required this.lomRef,
    required this.isLomStateResolved,
  });

  int get activePointerCount => _activeTracks.length;

  int? get soleActivePointerId =>
      _activeTracks.length == 1 ? _activeTracks.keys.first : null;

  bool hasActiveTrack(int pointerId) =>
      _activeTracks.containsKey(pointerId);

  TimedPosition? lastPositionFor(int pointerId) {
    final track = _activeTracks[pointerId];
    return track == null || track.positions.isEmpty
        ? null
        : track.positions.last;
  }

  bool join({
    required int pointerId,
    required int entryTimestamp,
    required TimedPosition initialPosition,
  }) {
    if (_activeTracks.containsKey(pointerId)) return false;

    final track = _PinchTrackState(
      pointerId: pointerId,
      entryTimestamp: entryTimestamp,
      positions: [initialPosition],
    );
    _tracks.add(track);
    _activeTracks[pointerId] = track;
    return true;
  }

  bool move(int pointerId, TimedPosition position) {
    final track = _activeTracks[pointerId];
    if (track == null) return false;
    track.positions.add(position);
    return true;
  }

  bool pointerUp(int pointerId, TimedPosition terminalPosition) {
    final track = _activeTracks.remove(pointerId);
    if (track == null) return false;
    track.positions.add(terminalPosition);
    track.exitTimestamp = terminalPosition.timestamp;
    return true;
  }

  bool pointerCancel(int pointerId, int timestamp) {
    final track = _activeTracks.remove(pointerId);
    if (track == null) return false;
    track.exitTimestamp = timestamp;
    return true;
  }

  PinchExplorationEvent? finish(int endTimestamp) {
    for (final track in _activeTracks.values) {
      track.exitTimestamp ??= endTimestamp;
    }
    _activeTracks.clear();

    final tracks = _tracks
        .where((track) => track.positions.isNotEmpty)
        .map(
          (track) => PinchTrack(
            pointerId: track.pointerId,
            entryDelta: track.entryTimestamp - startTimestamp,
            exitDelta: (track.exitTimestamp ?? endTimestamp) - startTimestamp,
            positions: sampleTimedPositions(track.positions)
                .map((position) => position.position)
                .toList(),
          ),
        )
        .toList();

    if (tracks.isEmpty) return null;
    return PinchExplorationEvent(
      timestamp: startTimestamp,
      viewport: viewport,
      endTimestamp: endTimestamp,
      tracks: tracks,
      lomRef: lomRef,
    );
  }
}

final class _PinchTrackState {
  final int pointerId;
  final int entryTimestamp;
  int? exitTimestamp;
  final List<TimedPosition> positions;

  _PinchTrackState({
    required this.pointerId,
    required this.entryTimestamp,
    required this.positions,
  });
}
