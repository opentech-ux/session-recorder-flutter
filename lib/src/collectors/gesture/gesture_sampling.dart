import 'package:session_recorder_flutter/src/models/models.dart';

List<TimedPosition> sampleTimedPositions(
  List<TimedPosition> positions, {
  int timestampThresholdMs = 50,
}) {
  if (positions.length <= 2) return positions;

  final sampled = <TimedPosition>[positions.first];
  var lastSaved = positions.first;

  for (var i = 1; i < positions.length; i++) {
    final current = positions[i];
    if (current.timestamp - lastSaved.timestamp >= timestampThresholdMs) {
      sampled.add(current);
      lastSaved = current;
    }
  }

  final last = positions.last;
  final alreadySaved = lastSaved.timestamp == last.timestamp &&
      lastSaved.position == last.position &&
      lastSaved.viewport == last.viewport;
  if (!alreadySaved) sampled.add(last);

  return sampled;
}
