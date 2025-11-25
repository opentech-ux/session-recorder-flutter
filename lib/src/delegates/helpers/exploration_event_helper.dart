import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

import '../../enums/gestures_type_enum.dart';
import '../../models/models.dart'
    show
        ExplorationEvent,
        PointerTrace,
        PanExplorationEvent,
        ZoomExplorationEvent,
        ScaleStats,
        TimedPosition,
        ViewportPosition,
        ScrollExplorationEvent;

class ExplorationEventHelper {
  /// Detects which [ExplorationEvent] gonna create it by the `pointers` type
  ///
  /// Could return a [PanExplorationEvent], [ZoomExplorationEvent] list
  static List<ExplorationEvent> detectTouchExplorationEvent(
    List<PointerTrace> pointers,
    Rect viewportScroll,
  ) {
    try {
      List<ExplorationEvent> explorationEvents = [];

      final pointer = pointers.last;

      switch (pointer.type) {
        case GesturesType.pan:
          explorationEvents = _getPanExploration(pointer, viewportScroll);
          break;
        case GesturesType.zoom:
          explorationEvents = _getZoomExploration(pointers, viewportScroll);

          break;

        default:
      }

      return explorationEvents;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return [];
    }
  }

  /// Converts the recorded [PointerTrace] data into a list of [PanExplorationEvent]
  /// instances.
  static List<PanExplorationEvent> _getPanExploration(
    PointerTrace pointerTrace,
    Rect viewportScroll,
  ) {
    try {
      if (pointerTrace.isEmpty) return [];

      List<PanExplorationEvent> panList = List.from(
        pointerTrace.positions.map(
          (touchDrag) => PanExplorationEvent(
            timestamp: touchDrag.timestamp,
            viewport: viewportScroll,
            position: touchDrag.position,
          ),
        ),
      );

      return panList;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return [];
    }
  }

  /// Converts the recorded [PointerTrace] data into a list of [ZoomExplorationEvent]
  /// instances.
  static List<ZoomExplorationEvent> _getZoomExploration(
    List<PointerTrace> pointers,
    Rect viewportScroll,
  ) {
    try {
      if (pointers.isEmpty) return [];

      final List<ZoomExplorationEvent> zoomList = [];

      for (int i = 0; i < pointers.length; i++) {
        final pointer = pointers[i];

        zoomList.add(
          ZoomExplorationEvent(
            timestamp: pointer.firstTimestamp!,
            endTimestamp: pointer.lastTimestamp!,
            viewport: viewportScroll,
            positions: pointer.positions.map((p) => p.position).toList(),
          ),
        );
      }

      return zoomList;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return [];
    }
  }

  /// Evaluates whether the current set of active pointers constitutes
  /// a zoom gesture.
  ///
  /// This method computes the centroid, mean distances, and directional
  /// vectors between fingers to determine if a scaling motion is occurring.
  ///
  /// Returns [true] if the average radial distance exceeds the `_scaleSlop`
  /// threshold and both fingers move consistently in a scaling direction.
  ///
  static bool evaluateZoomGesture(
    Map<int, PointerTrace> pointers,
    ScaleStats scaleStats,
  ) {
    try {
      if (scaleStats.scalePointers == null) return false;

      /// This block filters out most insignificant movements: if there is
      /// no relevant change in the average distance, it is not a zoom.
      final d0 = scaleStats.avgDistance ?? 0.0;

      /// Avoid divided by 0
      if (d0 <= 1e-6) return false;

      final cNow = MathUtils.getCentroid(scaleStats.scalePointers!);
      final dNow = MathUtils.getAverageDistance(pointers, cNow);

      final scale = MathUtils.getScale(d0, dNow);
      final scaleSensitivity = (scale - 1.0).abs();
      final scalePx = (dNow - d0).abs();

      /// If `scaleSensitivity` is less than `scaleThreshold` and `scalePx` is
      /// less than `scalePxThreshold` we consider it noise and not zoom.
      final bool maybeScale =
          (scaleSensitivity > scaleThreshold) || (scalePx > scalePxThreshold);

      if (!maybeScale) return false;

      final stats = MathUtils.analyzeFingerDirections(
        pointers,
        scaleStats.scalePointers!,
        scaleStats.centroid!,
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
          math.max(scaleSlop, radialToTang * stats.tangentialRms);

      /// Requires that the fraction of fingers pointing in the same radial
      /// direction be ≥ `consistencyFraction`
      final bool consistent = stats.consistency >= consistencyFraction;

      return radialDominates && consistent && maybeScale;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return false;
    }
  }

  /// Converts the recorded `scrollPanPositions` and `scrollViewportRects` data
  /// into a list of [ScrollExplorationEvent] and [PanExplorationEvent] instances.
  static List<ExplorationEvent> getScrollExploration(
    Map<int, Offset> scrollPanPositions,
    Map<int, Rect> scrollViewportRects,
  ) {
    try {
      final List<TimedPosition> positions = List<TimedPosition>.from(
        scrollPanPositions.entries
            .map((p) => TimedPosition(p.key, p.value))
            .toList(),
      );

      if (positions.isEmpty) return [];

      final List<ViewportPosition> viewportList = List<ViewportPosition>.from(
        scrollViewportRects.entries
            .map((p) => ViewportPosition(p.key, p.value))
            .toList(),
      );

      if (viewportList.isEmpty) return [];

      int lastTs = positions.first.timestamp;

      final panEvents = <ExplorationEvent>[];

      for (TimedPosition position in positions) {
        final int ts = position.timestamp;

        final tsRelative = ts - lastTs;

        final int viewportIndex = viewportList.indexWhere(
          (s) => s.timestamp == ts,
        );

        if (viewportIndex != -1) {
          final viewport = viewportList.elementAt(viewportIndex);

          int panScrollThreshold = 50;

          if (positions.length <= 10) {
            panScrollThreshold = 20;
          }

          if (tsRelative >= panScrollThreshold) {
            panEvents.add(
              PanExplorationEvent(
                timestamp: position.timestamp,
                viewport: viewport.viewport,
                position: position.position,
              ),
            );
            lastTs = ts;
          }
        }
      }

      final firstScrollViewport = viewportList.firstWhere(
        (v) => positions.any((p) => p.timestamp == v.timestamp),
        orElse: () => viewportList.first,
      );

      final lastScrollViewport = viewportList.lastWhere(
        (v) => positions.any((p) => p.timestamp == v.timestamp),
        orElse: () => viewportList.last,
      );

      if (firstScrollViewport == lastScrollViewport) return [];

      List<ExplorationEvent> scrollExplorationEvents = [
        ScrollExplorationEvent(
          timestamp: firstScrollViewport.timestamp,
          viewport: firstScrollViewport.viewport,
          phase: ScrollPhase.start,
        ),
        ...panEvents,
        ScrollExplorationEvent(
          timestamp: lastScrollViewport.timestamp,
          viewport: lastScrollViewport.viewport,
          phase: ScrollPhase.end,
        ),
      ];

      scrollPanPositions.clear();
      scrollViewportRects.clear();

      return scrollExplorationEvents;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return [];
    }
  }
}
