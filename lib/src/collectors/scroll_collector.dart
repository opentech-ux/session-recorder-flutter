import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
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
  bool _isTabBarPageScroll = false;
  Rect? _activeViewportBounds;
  Offset _activeOffset = Offset.zero;
  Timer? _tabCaptureTimer;

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

    final geometry = _captureScrollGeometry(
      context,
      scrollMetrics,
      reuseActiveBounds: notification is! ScrollStartNotification,
    );
    if (geometry == null) {
      if (notification is ScrollEndNotification) {
        final captureTab = _isTabBarPageScroll;
        _isScrolling = false;
        _isTabBarPageScroll = false;
        _activeViewportBounds = null;
        _activeOffset = Offset.zero;
        _engine.context.setCurrentlyScrolling(false);
        _clearScrollViewport();
        if (captureTab) _scheduleTabCapture();
      }
      return false;
    }

    if (notification is ScrollStartNotification) {
      _tabCaptureTimer?.cancel();
      _isScrolling = true;
      _isTabBarPageScroll = _matchesTabBarPager(
        context,
        scrollMetrics,
        geometry.viewport,
      );
      _activeViewportBounds = geometry.viewport;
      _activeOffset = geometry.offset;
      _engine.context.setCurrentlyScrolling(true);

      _engine.context.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: geometry.viewport,
          offset: geometry.offset,
          phase: ScrollPhase.start,
          lomRef: _engine.context.currentLomRef ?? '',
        ),
      );
    } else if (notification is ScrollUpdateNotification) {
      _activeViewportBounds = geometry.viewport;
      _activeOffset = geometry.offset;
    } else if (notification is ScrollEndNotification) {
      final captureTab = _isTabBarPageScroll;
      _isScrolling = false;
      _isTabBarPageScroll = false;
      _activeViewportBounds = null;

      _engine.context.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: geometry.viewport,
          offset: geometry.offset,
          phase: ScrollPhase.end,
          lomRef: _engine.context.currentLomRef ?? '',
        ),
      );

      _activeOffset = Offset.zero;
      _engine.context.setCurrentlyScrolling(false);

      _clearScrollViewport();
      if (captureTab) _scheduleTabCapture();
    }

    return false;
  }

  /// Captures the fixed viewport and the content offset separately.
  _ScrollGeometry? _captureScrollGeometry(
    BuildContext context,
    ScrollMetrics metrics, {
    required bool reuseActiveBounds,
  }) {
    final physicalRect = reuseActiveBounds && _activeViewportBounds != null
        ? _activeViewportBounds
        : _findPhysicalViewport(context);

    if (physicalRect == null) return null;

    try {
      final pixels = metrics.pixels
          .clamp(metrics.minScrollExtent, metrics.maxScrollExtent)
          .toDouble();
      final offset = switch (metrics.axisDirection) {
        AxisDirection.down => Offset(0, pixels),
        AxisDirection.up => Offset(0, -pixels),
        AxisDirection.right => Offset(pixels, 0),
        AxisDirection.left => Offset(-pixels, 0),
      };

      _engine.context.setScrollPhysicalBounds(physicalRect);

      return _ScrollGeometry(viewport: physicalRect, offset: offset);
    } catch (e) {
      return null;
    }
  }

  /// Finds the viewport built by this Scrollable, before any nested viewport.
  Rect? _findPhysicalViewport(BuildContext context) {
    final root = context.findRenderObject();
    if (root == null) return null;

    RenderAbstractViewport? viewport;

    void find(RenderObject child) {
      if (viewport != null) return;
      if (child is RenderAbstractViewport) {
        viewport = child;
        return;
      }
      child.visitChildren(find);
    }

    find(root);
    return MathUtils.transformRect(viewport ?? root);
  }

  /// Identifies the PageView owned by a TabBarView, not nested carousels.
  bool _matchesTabBarPager(
    BuildContext context,
    ScrollMetrics metrics,
    Rect viewport,
  ) {
    var matches = false;
    var pageViewCount = 0;
    var hasNestedScrollView = false;

    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is PageView) pageViewCount++;
      if (widget is ScrollView) hasNestedScrollView = true;
      if (widget is! TabBarView) return true;

      final controller =
          widget.controller ?? DefaultTabController.maybeOf(element);
      final renderObject = element.renderObject;
      final tabBounds = renderObject == null
          ? null
          : MathUtils.transformRect(renderObject);
      final expectedExtent = controller == null
          ? double.nan
          : metrics.viewportDimension * (controller.length - 1);

      bool closeTo(double left, double right) => (left - right).abs() <= 1;

      matches =
          metrics.axis == Axis.horizontal &&
          pageViewCount == 1 &&
          !hasNestedScrollView &&
          tabBounds != null &&
          closeTo(viewport.left, tabBounds.left) &&
          closeTo(viewport.top, tabBounds.top) &&
          closeTo(viewport.width, tabBounds.width) &&
          closeTo(viewport.height, tabBounds.height) &&
          closeTo(metrics.minScrollExtent, 0) &&
          closeTo(metrics.maxScrollExtent, expectedExtent);
      return false;
    });

    return matches;
  }

  /// Captures the active tab once its page transition has settled.
  void _scheduleTabCapture() {
    _tabCaptureTimer?.cancel();
    _tabCaptureTimer = Timer(kScrollCaptureSettleTime, () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _engine.context.captureTree(false);
      });
    });
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    _tabCaptureTimer?.cancel();
    if (!_isScrolling) return;

    if (_activeViewportBounds != null) {
      _engine.context.recordExploration(
        ScrollExplorationEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          viewport: _activeViewportBounds!,
          offset: _activeOffset,
          phase: ScrollPhase.end,
          lomRef: _engine.context.currentLomRef ?? '',
        ),
      );
    }

    _isScrolling = false;
    _isTabBarPageScroll = false;
    _activeViewportBounds = null;
    _activeOffset = Offset.zero;
    _engine.context.setCurrentlyScrolling(false);
    _clearScrollViewport();
  }

  /// Clears stale scroll geometry after the scroll session ends.
  void _clearScrollViewport() {
    _engine.context.setScrollPhysicalBounds(Rect.zero);
  }
}

class _ScrollGeometry {
  final Rect viewport;
  final Offset offset;

  const _ScrollGeometry({required this.viewport, required this.offset});
}
