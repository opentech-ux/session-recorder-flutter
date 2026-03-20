import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';

/// Collects scroll position data and emits one [ScrollSessionEndEvent] per
/// gesture.
class ScrollCollector {
  final SessionRecorderInternal _recorder;

  ScrollCollector(this._recorder);

  /// Caches of the recent scroll viewport
  Rect _scrollableRect = Rect.zero;

  /// Handles incoming [ScrollNotification] events to detect and record scroll
  /// interactions.
  bool handleScrollNotification(ScrollNotification notification) {
    final context = notification.context;

    if (context == null) return false;

    final scrollableState = Scrollable.maybeOf(context);

    if (notification is! OverscrollNotification) {
      ScrollPosition scrollPosition;

      if (scrollableState != null) {
        scrollPosition = scrollableState.position;
      } else {
        scrollPosition = notification.metrics as ScrollPosition;
      }

      _captureViewportGeometry(context, scrollPosition);
      _recorder.setViewport(_scrollableRect);

      if (notification is ScrollStartNotification) {
        _recorder.recordExploration(
          ScrollExplorationEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            viewport: _scrollableRect,
            phase: ScrollPhase.start,
          ),
        );

        return false;
      }

      if (notification is ScrollEndNotification) {
        _recorder.recordExploration(
          ScrollExplorationEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            viewport: _scrollableRect,
            phase: ScrollPhase.end,
          ),
        );
      }
    }

    return false;
  }

  /// Computes and updates the current viewport rectangle for a scrollable
  /// position.
  void _captureViewportGeometry(
    BuildContext context,
    ScrollPosition? scrollPosition,
  ) {
    final renderObject = context.findRenderObject();

    if (renderObject is! RenderBox) return;

    final initPosition = renderObject.localToGlobal(Offset.zero);

    final rect = initPosition & renderObject.size;

    _scrollableRect = rect;

    if (scrollPosition == null) return;

    final double contentHeight =
        scrollPosition.maxScrollExtent + scrollPosition.viewportDimension;
    final double left = rect.left;
    final double contentTop = rect.top - scrollPosition.pixels;

    _scrollableRect = Rect.fromLTWH(
      left,
      contentTop,
      rect.width,
      contentHeight,
    );
  }
}
