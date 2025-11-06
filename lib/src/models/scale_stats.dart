import 'package:flutter/material.dart';

import 'models.dart';

class ScaleStats {
  /// The geometric center (average position) of all active fingers.
  /// Used as the focal point for measuring scale and distance changes.
  Offset? centroid;

  /// The average distance from each active finger to the [centroid].
  /// Represents the overall "spread" of the touch points
  double? avgDistance;

  /// The collection of all active [PointerTrace] objects participating in
  /// the scale gesture.
  Map<int, PointerTrace>? scalePointers;

  ScaleStats({
    required this.centroid,
    required this.avgDistance,
    required this.scalePointers,
  });

  factory ScaleStats.zero() => ScaleStats(
        centroid: null,
        avgDistance: null,
        scalePointers: null,
      );

  @override
  String toString() =>
      'ScaleStats(centroid: $centroid, avgDistance: $avgDistance, scalePointers: $scalePointers)';
}
