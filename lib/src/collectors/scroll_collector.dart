import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

/// Collects scroll position data and emits one [ScrollSessionEndEvent] per
/// gesture.
class ScrollCollector {
  static const double _movementTolerance = 1.0;
  static const Duration _captureStabilization = Duration(milliseconds: 600);

  final SessionRecorderEngineInternal _engine;

  ScrollCollector({SessionRecorderEngineInternal? engine})
    : _engine = engine ?? SessionRecorder.engine;

  bool _isScrolling = false;
  bool _isValidated = false;
  bool _isDisposed = false;
  ScrollExplorationEvent? _provisionalStart;
  Rect? _activeViewportBounds;
  Offset? _initialOffset;
  Offset? _activeOffset;
  Timer? _captureTimer;

  /// Handles incoming [ScrollNotification] events to detect and record scroll
  /// interactions.
  bool handleScrollNotification(ScrollNotification notification) {
    if (_isDisposed) return false;
    if (notification is OverscrollNotification) return false;
    if (notification is! ScrollStartNotification &&
        notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _handleScrollStart(notification);
    } else if (notification is ScrollUpdateNotification) {
      _handleScrollUpdate(notification.context, notification.metrics);
    } else if (notification is ScrollEndNotification) {
      _handleScrollEnd(notification.context, notification.metrics);
    }

    return false;
  }

  void _handleScrollStart(ScrollStartNotification notification) {
    _cancelPendingCapture();

    if (_isScrolling) {
      try {
        _finishSession(scheduleCapture: false);
      } catch (_) {
        _releaseSuppressionAndReset();
      }
    }

    final rect = _captureViewportGeometry(notification.context);
    final offset = _effectiveOffset(notification.metrics);
    if (rect == null || offset == null) return;

    _isScrolling = true;
    _isValidated = false;
    _activeViewportBounds = rect;
    _initialOffset = offset;
    _activeOffset = offset;
    _provisionalStart = ScrollExplorationEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      viewport: rect,
      phase: ScrollPhase.start,
      offset: offset,
      lomRef: _engine.context.currentLomRef ?? '',
    );
    _engine.context.setScrollActive(true);
  }

  void _handleScrollUpdate(
    BuildContext? context,
    ScrollMetrics scrollMetrics,
  ) {
    if (!_isScrolling) return;

    final rect = _captureViewportGeometry(context);
    if (rect != null) _activeViewportBounds = rect;

    final offset = _effectiveOffset(scrollMetrics);
    if (offset == null) return;

    _activeOffset = offset;
    _validateMovement(offset);
  }

  void _handleScrollEnd(
    BuildContext? context,
    ScrollMetrics scrollMetrics,
  ) {
    if (!_isScrolling) return;

    try {
      final rect = _captureViewportGeometry(context);
      if (rect != null) _activeViewportBounds = rect;

      final offset = _effectiveOffset(scrollMetrics);
      if (offset != null) {
        _activeOffset = offset;
        _validateMovement(offset);
      }

      _finishSession();
    } catch (_) {
      _releaseSuppressionAndReset();
    }
  }

  /// Computes the visible viewport rectangle for a scrollable.
  Rect? _captureViewportGeometry(BuildContext? context) {
    if (context == null) return null;

    try {
      final view = View.maybeOf(context);
      if (view == null) return null;

      final devicePixelRatio = view.devicePixelRatio;
      final physicalSize = view.physicalSize;
      if (!devicePixelRatio.isFinite ||
          devicePixelRatio <= 0 ||
          !physicalSize.width.isFinite ||
          !physicalSize.height.isFinite ||
          physicalSize.width <= 0 ||
          physicalSize.height <= 0) {
        return null;
      }

      final viewportWidth = physicalSize.width / devicePixelRatio;
      final viewportHeight = physicalSize.height / devicePixelRatio;
      if (!viewportWidth.isFinite ||
          !viewportHeight.isFinite ||
          viewportWidth <= 0 ||
          viewportHeight <= 0) {
        return null;
      }

      final renderObject = context.findRenderObject();
      final rect = MathUtils.transformRect(renderObject);

      if (rect == null || !rect.isFinite || rect.isEmpty) return null;

      final viewport = Rect.fromLTWH(0, 0, viewportWidth, viewportHeight);
      final visibleRect = rect.intersect(viewport);
      if (!visibleRect.isFinite ||
          visibleRect.width <= 0 ||
          visibleRect.height <= 0) {
        return null;
      }

      return visibleRect;
    } catch (_) {
      return null;
    }
  }

  Offset? _effectiveOffset(ScrollMetrics scrollMetrics) {
    try {
      final pixels = scrollMetrics.pixels;
      final min = scrollMetrics.minScrollExtent;
      final max = scrollMetrics.maxScrollExtent;

      if (pixels.isNaN || min.isNaN || max.isNaN || min > max) return null;

      final effectivePixels = pixels.clamp(min, max).toDouble();
      if (!effectivePixels.isFinite) return null;

      return scrollMetrics.axis == Axis.horizontal
          ? Offset(effectivePixels, 0)
          : Offset(0, effectivePixels);
    } catch (_) {
      return null;
    }
  }

  void _validateMovement(Offset offset) {
    if (_isValidated) return;

    final initialOffset = _initialOffset;
    final provisionalStart = _provisionalStart;
    if (initialOffset == null || provisionalStart == null) return;

    if ((offset - initialOffset).distance <= _movementTolerance) return;

    _engine.context.recordExploration(provisionalStart);
    _isValidated = true;
    _engine.context.markPostScrollCapturePending();
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    if (_isDisposed || !_isScrolling) return;

    try {
      _finishSession();
    } catch (_) {
      _releaseSuppressionAndReset();
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _cancelPendingCapture();

    if (_isScrolling) {
      try {
        _engine.context.setScrollActive(false);
      } finally {
        _resetSessionState();
      }
      return;
    }

    _resetSessionState();
  }

  void _finishSession({bool scheduleCapture = true}) {
    try {
      final viewport = _activeViewportBounds;
      final offset = _activeOffset;

      if (_isValidated && viewport != null && offset != null) {
        _engine.context.recordExploration(
          ScrollExplorationEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            viewport: viewport,
            phase: ScrollPhase.end,
            offset: offset,
            lomRef: _engine.context.currentLomRef ?? '',
          ),
        );
      }
    } finally {
      _releaseSuppressionAndReset();
    }

    if (scheduleCapture &&
        _engine.context.hasPendingPostScrollCapture) {
      _scheduleStabilizedCapture();
    }
  }

  void _releaseSuppressionAndReset() {
    try {
      _engine.context.setScrollActive(false);
    } finally {
      _resetSessionState();
    }
  }

  void _resetSessionState() {
    _isScrolling = false;
    _isValidated = false;
    _provisionalStart = null;
    _activeViewportBounds = null;
    _initialOffset = null;
    _activeOffset = null;
  }

  void _scheduleStabilizedCapture() {
    if (_isDisposed) return;
    _cancelPendingCapture();

    late final Timer timer;
    timer = Timer(_captureStabilization, () {
      if (_isDisposed || !identical(_captureTimer, timer)) return;
      _captureTimer = null;

      try {
        _engine.context.capturePendingPostScrollLom();
      } catch (_) {
        // Tree capture stays fail-open.
      }
    });
    _captureTimer = timer;
  }

  void _cancelPendingCapture() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }
}
