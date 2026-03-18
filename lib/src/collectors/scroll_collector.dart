import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';

/// Detects scroll gestures from [ScrollNotification] bubbled up the widget tree.
class ScrollCollector {
  final SessionRecorderInternal _recorder;

  ScrollCollector(this._recorder);

  ScrollSession? _scrollSession;

  /// Handles incoming [ScrollNotification] events to detect and record scroll
  /// interactions.
  bool handleScrollNotification(ScrollNotification notification) {
    final context = notification.context;

    if (context == null) return false;

    final scrollableState = Scrollable.maybeOf(context);

    ScrollPosition scrollPosition;

    if (scrollableState != null) {
      scrollPosition = scrollableState.position;
    } else {
      scrollPosition = notification.metrics as ScrollPosition;
    }

    if (notification is ScrollStartNotification) {
      _scrollSession = ScrollSession(startPixel: scrollPosition.pixels);
      _recorder.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: Rect.zero,
          phase: ScrollPhase.start,
        ),
      );

      return false;
    }

    if (_scrollSession == null) return false;

    final double pixel = scrollPosition.pixels;

    if (notification is ScrollUpdateNotification) {
      if (_scrollSession == null) return false;
      if ((pixel - _scrollSession!.positions.last).abs() >= scrollSlop) {
        _scrollSession!.positions.add(pixel);
      }
    }

    if (notification is ScrollEndNotification) {
      final ScrollSession scrollSession = _scrollSession!;
      _scrollSession = null;

      if (scrollSession.positions.last != scrollPosition.pixels) {
        scrollSession.positions.add(pixel);
      }

      _recorder.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: Rect.zero,
          phase: ScrollPhase.end,
        ),
      );
    }

    return false;
  }
}
