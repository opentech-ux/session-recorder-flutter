import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

/// Collects scroll position data and emits one [ScrollSessionEndEvent] per
/// gesture.
class ScrollCollector {
  final SessionRecorderEngineInternal _engine;

  ScrollCollector({SessionRecorderEngineInternal? engine})
    : _engine = engine ?? SessionRecorder.engine;

  bool _isScrolling = false;
  Rect? _activeViewportBounds;

  /// Handles incoming [ScrollNotification] events to detect and record scroll
  /// interactions.
  bool handleScrollNotification(ScrollNotification notification) {
    final context = notification.context;

    if (context == null || notification is OverscrollNotification) return false;
    if (notification is! ScrollStartNotification &&
        notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }

    final scrollMetrics = notification.metrics;

    final rect = _captureViewportGeometry(context, scrollMetrics);
    if (rect == null) return false;

    if (notification is ScrollStartNotification) {
      _isScrolling = true;
      _activeViewportBounds = rect;

      _engine.context.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: rect,
          phase: ScrollPhase.start,
        ),
      );
    } else if (notification is ScrollUpdateNotification) {
      _activeViewportBounds = rect;
    } else if (notification is ScrollEndNotification) {
      _isScrolling = false;
      _activeViewportBounds = null;

      _engine.context.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: rect,
          phase: ScrollPhase.end,
        ),
      );

      _clearScrollViewport();
    }

    return false;
  }

  /// Computes and updates the current viewport rectangle for a scrollable
  /// position.
  Rect? _captureViewportGeometry(
    BuildContext context,
    ScrollMetrics scrollMetrics,
  ) {
    final renderObject = context.findRenderObject();
    final physicalRect = MathUtils.transformRect(renderObject);

    if (physicalRect == null) return null;

    try {
      double contentWidth = physicalRect.width;
      double contentHeight = physicalRect.height;
      double contentLeft = physicalRect.left;
      double contentTop = physicalRect.top;

      if (scrollMetrics.axis == Axis.vertical) {
        contentHeight =
            scrollMetrics.maxScrollExtent + scrollMetrics.viewportDimension;
        contentTop = physicalRect.top - scrollMetrics.pixels;
      } else {
        contentWidth =
            scrollMetrics.maxScrollExtent + scrollMetrics.viewportDimension;
        contentLeft = physicalRect.left - scrollMetrics.pixels;
      }

      final virtualRect = Rect.fromLTWH(
        contentLeft,
        contentTop,
        contentWidth,
        contentHeight,
      );

      _engine.context.setScrollPhysicalBounds(physicalRect);
      _engine.context.setScrollVirtualCanvas(virtualRect);

      return virtualRect;
    } catch (e) {
      return null;
    }
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    if (_isScrolling && _activeViewportBounds != null) {
      _engine.context.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: _activeViewportBounds!,
          phase: ScrollPhase.end,
        ),
      );

      _isScrolling = false;
      _activeViewportBounds = null;
      _clearScrollViewport();
    }
  }

  /// Clears stale scroll geometry after the scroll session ends.
  void _clearScrollViewport() {
    _engine.context.setScrollPhysicalBounds(Rect.zero);
    _engine.context.setScrollVirtualCanvas(Rect.zero);
  }
}
