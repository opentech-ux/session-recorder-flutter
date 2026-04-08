import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';

import '../models/models.dart'
    show PointerTrace, PinchMetricsBaseline, PinchStats;

class MathUtils {
  /// Calculates the centroid (average of positions) of all active fingers.
  ///
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
    final positions = pointers.values
        .map((pointer) => pointer.lastPosition)
        .toList();
    final sum = positions.fold(Offset.zero, (last, current) => last + current);
    return sum / positions.length.toDouble();
  }

  /// Calculates the average distance of all fingers to the given centroid.
  ///
  static double getAverageDistance(Map<int, PointerTrace> pointers) {
    if (pointers.length < 2) return 0;

    final positions = pointers.values
        .map((pointer) => pointer.lastPosition)
        .toList();

    final centroid = getCentroid(pointers);

    return positions
            .map((p) => (p - centroid).distance)
            .reduce((a, b) => a + b) /
        positions.length;
  }

  /// Get the scale divide by the `secondDistance` and `firstDistance`
  static double getScale(double firstDistance, double secondDistance) =>
      secondDistance / firstDistance;

  /// Evaluates whether the current set of active pointers constitutes
  /// a zoom gesture.
  ///
  /// This method computes the centroid, mean distances, and directional
  /// vectors between fingers to determine if a scaling motion is occurring.
  ///
  /// Returns `[true]` if the average radial distance exceeds the `pinchSlop`
  /// threshold and both fingers move consistently in a scaling direction.
  ///
  static bool evaluatePinchGesture(
    Map<int, PointerTrace> pointers,
    PinchMetricsBaseline pinchMetrics,
  ) {
    if (pinchMetrics.initialPositions == null) return false;

    /// This block filters out most insignificant movements: if there is
    /// no relevant change in the average distance, it is not a zoom.
    final d0 = pinchMetrics.avgDistance ?? 0.0;

    /// Avoid divided by 0
    if (d0 <= 1e-6) return false;

    // final cNow = MathUtils.getCentroid(pinchMetrics.scalePointers!);
    final dNow = MathUtils.getAverageDistance(pointers);

    final scale = MathUtils.getScale(d0, dNow);
    final scaleSensitivity = (scale - 1.0).abs();
    final scalePx = (dNow - d0).abs();

    /// If `scaleSensitivity` is less than `pinchThreshold` and `scalePx` is
    /// less than `pinchPxThreshold` we consider it noise and not zoom.
    final bool maybePinch =
        (scaleSensitivity > pinchThreshold) || (scalePx > pinchPxThreshold);

    if (!maybePinch) return false;

    final stats = MathUtils.analyzeFingerDirections(
      pointers,
      pinchMetrics.initialPositions!,
      pinchMetrics.centroid!,
    );

    /// We check that the absolute value of `avgRadial` is greater than:
    ///
    /// - `touchSlop`
    /// - `radialToTang` * `tangRms` (i.e., that the radial is several times
    ///   greater than the typical lateral movement).
    ///
    /// `math.max()` uses the greater of the two thresholds, so radial
    /// must exceed the more demanding one.
    final bool radialDominates =
        stats.avgRadial.abs() >
        math.max(pinchSlop, radialToTang * stats.tangentialRms);

    /// Requires that the fraction of fingers pointing in the same radial
    /// direction be ≥ `consistencyFraction`
    final bool consistent = stats.consistency >= consistencyFraction;

    return radialDominates && consistent && maybePinch;
  }

  /// Analyzes the movement of each finger to measure [Radial] and [Tangential],
  /// then we calculate how consistent those movements between the fingers are.
  ///
  /// Fingers can move:
  /// - __Radial__ : Outward or inward from the center (zoom in/zoom out)
  /// - __Tangential__ : Rotating around the center (rotation)
  /// - In chaotic or inconsistent directions, neither clear zoom nor rotation
  ///
  /// Returns a [PinchStats] object.
  static PinchStats analyzeFingerDirections(
    Map<int, PointerTrace> pointers,
    Map<int, Offset> initialPointers,
    Offset initialCentroid,
  ) {
    double sumRadial = 0.0, sumTangentialSq = 0.0;

    int positives = 0, negatives = 0, counted = 0;

    for (int pointer in initialPointers.keys) {
      if (!pointers.containsKey(pointer)) continue;

      /// Initial position
      final p0 = initialPointers[pointer]!;

      /// Current position
      final pNow = pointers[pointer]!.lastPosition;

      /// Vector pointing from the initial center to the initial position
      /// of the finger.
      final rVec = p0 - (initialCentroid);
      final rDis = rVec.distance;

      /// If the finger was exactly at the initial center, continues.
      if (rDis <= 1e-6) continue;

      /// The [Finger's Movement Vector]: how much the finger moved.
      final v = pNow - p0;

      if (v.distance < 3.0) continue;

      /// The [Radial Unit Vector]: normalized radial direction (length 1).
      final u = Offset(rVec.dx / rDis, rVec.dy / rDis);

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

    if (counted == 0) return PinchStats.zero();

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

    return PinchStats(
      avgRadial: avgRadial,
      tangentialRms: tangRms,
      consistency: consistency,
    );
  }
}
