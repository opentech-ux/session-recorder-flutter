import 'package:flutter/material.dart';

@immutable
class PinchMetricsBaseline {
  /// The geometric center (average position) of all active fingers.
  /// Used as the focal point for measuring pinch and distance changes.
  final Offset? centroid;

  /// The average distance from each active finger to the [centroid].
  /// Represents the overall "spread" of the touch points
  final double? avgDistance;

  /// The collection of all the initial positions
  final Map<int, Offset>? initialPositions;

  const PinchMetricsBaseline({
    required this.centroid,
    required this.avgDistance,
    required this.initialPositions,
  });

  @override
  String toString() =>
      'PinchMetricsBaseline(centroid: $centroid, avgDistance: $avgDistance, initialPositions: $initialPositions)';
}
