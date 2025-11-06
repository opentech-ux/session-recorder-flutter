import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart' show PointerTrace, ZoomStats;

class MathUtils {
  /// Calculates the centroid (average of positions) of all active fingers.
  ///
  /// The pointer events are captured with a Listener and the centroid of
  /// the touches and the average distance to the center are calculated
  /// explicitly. The centroid of `N` fingers is the average of their
  /// coordinates:
  /// ```
  /// Centroid = ((∑i ​xi) / 𝑁,(∑i ​yi) / 𝑁​​)
  /// ```
  /// __Example :__
  ///
  /// ```
  ///   (x1, y1)
  ///       ●
  ///        (Centroid)
  ///(x3, y3)   ●  (x2, y2)
  ///    ●             ●
  /// ```
  ///
  static Offset getCentroid(Map<int, PointerTrace> pointers) {
    double x = 0, y = 0;

    for (PointerTrace p in pointers.values) {
      x += p.lastPosition!.dx;
      y += p.lastPosition!.dy;
    }

    return Offset(
      x / pointers.length,
      y / pointers.length,
    );
  }

  /// Calculates the average distance of all fingers to the given centroid.
  ///
  /// The average distance is the arithmetic mean of the distances
  /// from each finger to that centroid. When the fingers move, the scale
  /// factor is obtained as the ratio between the current and initial
  /// average distances
  /// ```
  /// d = 1/N ​∑i​ ∥ pi ​− C ∥
  /// ```
  ///
  /// Add up all the distances and divide by the number of fingers
  ///
  /// ```
  /// " ∥ pi ​− C ∥ " : take the length of that vector
  /// ```
  static double getAverageDistance(
    Map<int, PointerTrace> pointers,
    Offset center,
  ) {
    if (pointers.isEmpty) return 0.0;

    double sum = 0;

    for (PointerTrace p in pointers.values) {
      sum += (p.lastPosition! - center).distance;
    }

    return sum / pointers.length;
  }

  /// Get the scale divide by the `secondDistance` and `firstDistance`
  static double getScale(
    double firstDistance,
    double secondDistance,
  ) =>
      secondDistance / firstDistance;

  /// Analyzes the movement of each finger to measure [Radial] and [Tangential],
  /// then we calculate how consistent those movements between the fingers are.
  ///
  /// Fingers can move:
  /// - __Radial__ : Outward or inward from the center (zoom in/zoom out)
  /// - __Tangential__ : Rotating around the center (rotation)
  /// - In chaotic or inconsistent directions, neither clear zoom nor rotation
  ///
  /// Returns a [ZoomStats] object.
  static ZoomStats analyzeFingerDirections(
    Map<int, PointerTrace> pointers,
    Map<int, PointerTrace> initialPointers,
    Offset initialCentroid,
  ) {
    double sumRadial = 0.0, sumTangentialSq = 0.0;

    int positives = 0, negatives = 0, counted = 0;

    for (int pointer in initialPointers.keys) {
      if (!pointers.containsKey(pointer)) continue;

      /// Initial position
      final p0 = initialPointers[pointer]!.lastPosition!;

      /// Current position
      final pNow = pointers[pointer]!.lastPosition!;

      /// Vector pointing from the initial center to the initial position
      /// of the finger.
      final rVec = p0 - (initialCentroid);
      final rDis = rVec.distance;

      /// If the finger was exactly at the initial center, continues.
      if (rDis <= 1e-6) continue;

      /// The [Radial Unit Vector]: normalized radial direction (length 1).
      final u = Offset(rVec.dx / rDis, rVec.dy / rDis);

      /// The [Finger's Movement Vector]: how much the finger moved.
      final v = pNow - p0;

      /// How much of the movement is toward/away from the center.
      /// ```
      /// - radial > 0 : zoom out
      /// - radial < 0 : zoom in
      /// - radial = 0 : rotation around or perpendicular displacement
      /// ```
      final radial = v.dx * u.dx + v.dy * u.dy;

      sumRadial += radial;

      /// Perpendicular part (rotation/lateral displacement).
      ///
      /// This subtraction eliminates the radial part of the movement;
      /// what remains is the perpendicular (tangential) part.
      final tx = v.dx - radial * u.dx;
      final ty = v.dy - radial * u.dy;

      sumTangentialSq += tx * tx + ty * ty;

      if (radial > 0) {
        positives++;
      } else if (radial < 0) {
        negatives++;
      }

      counted++;
    }

    if (counted == 0) return ZoomStats.zero();

    // * METRICS

    /// Average of radial projections (can be positive or negative)
    /// ```
    /// - If positive : on average, the fingers move apart.
    /// - If negative : on average, they move closer together.
    /// ```
    final avgRadial = counted > 0 ? sumRadial / counted.toDouble() : 0.0;

    /// √(mean of the squares of tangential components)
    ///
    /// This is the typical magnitude of lateral movement. We use
    /// RMS to obtain a robust measurement in the face of opposing
    /// directions.
    final tangRms = math.sqrt(sumTangentialSq / counted.toDouble());

    /// Fraction of fingers that share the same majority radial direction.
    ///
    /// Example :
    /// ```
    /// 3 fingers, 2 moving away, 1 moving closer → 2/3 = 0.66 consistency
    /// If everyone does the same → 3/3 = 1.0 consistency
    /// ```
    /// Measures whether the majority of fingers “agree” to move away or
    /// closer together.
    final consistency = (math.max(positives, negatives) / counted.toDouble());

    return ZoomStats(
      avgRadial: avgRadial,
      tangentialRms: tangRms,
      consistency: consistency,
    );
  }
}
