import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_engine.dart';

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

    final scrollMetrics = notification.metrics;

    final rect = _captureViewportGeometry(context, scrollMetrics);
    if (rect == null) return false;

    if (notification is ScrollStartNotification) {
      _isScrolling = true;
      _activeViewportBounds = rect;

      _engine.recorder.recordExploration(
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

      _engine.recorder.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: rect,
          phase: ScrollPhase.end,
        ),
      );
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
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final initPosition = renderObject.localToGlobal(Offset.zero);
    final physicalRect = initPosition & renderObject.size;

    final double contentHeight =
        scrollMetrics.maxScrollExtent + scrollMetrics.viewportDimension;
    final double contentTop = physicalRect.top - scrollMetrics.pixels;

    final virtualRect = Rect.fromLTWH(
      physicalRect.left,
      contentTop,
      physicalRect.width,
      contentHeight,
    );

    _engine.recorder.setScrollPhysicalBounds(physicalRect);
    _engine.recorder.setScrollVirtualCanvas(virtualRect);

    return virtualRect;
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    if (_isScrolling && _activeViewportBounds != null) {
      _engine.recorder.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: _activeViewportBounds!,
          phase: ScrollPhase.end,
        ),
      );

      _isScrolling = false;
      _activeViewportBounds = null;
    }
  }
}
