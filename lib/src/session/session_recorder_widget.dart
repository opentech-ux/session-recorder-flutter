import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/collectors/gestures_collector.dart';
import 'package:session_recorder_flutter/src/collectors/scroll_collector.dart';
import 'package:session_recorder_flutter/src/observers/session_lifecycle_observer.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_overlay.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';

/// {@template session_recorder_widget}
/// Defines the capture boundary for an application subtree.
/// Its existing [Listener] supplies the stable physical capture anchor used by
/// [TreeDetector].
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SessionRecorderWidget(
///     child: child ?? const SizedBox.shrink(),
///   ),
/// );
/// ```
///
/// Install it once after `SessionRecorder.init`. Placement in
/// `MaterialApp.builder` or `MaterialApp.router.builder` is recommended.
/// [SessionNavigatorObserver] is optional.
/// {@endtemplate}
class SessionRecorderWidget extends StatefulWidget {
  final Widget child;

  ///{@macro session_recorder_widget}
  const SessionRecorderWidget({super.key, required this.child});

  /// Convenience outer-wrapper integration that provides an optional
  /// [SessionNavigatorObserver] to [builder].
  ///
  /// ```dart
  /// SessionRecorderWidget.observer(
  ///   builder: (observer) => MaterialApp(
  ///     navigatorObservers: [existingObserver, observer],
  ///     home: const HomeScreen(),
  ///   ),
  /// );
  /// ```
  ///
  /// Invoke it once after `SessionRecorder.init`. Use the regular constructor
  /// in `MaterialApp.builder` when the recommended, narrower boundary is
  /// preferred.
  static Widget observer({
    Key? key,
    required Widget Function(SessionNavigatorObserver observer) builder,
  }) {
    final observer = SessionNavigatorObserver();
    return SessionRecorderWidget(key: key, child: builder(observer));
  }

  @override
  State<SessionRecorderWidget> createState() => _SessionRecorderWidgetState();
}

class _SessionRecorderWidgetState extends State<SessionRecorderWidget>
    with WidgetsBindingObserver, SessionLifecycleObserver {
  late final GestureCollector _gestures;
  late final ScrollCollector _scrolls;
  Element? _captureElement;

  @override
  void initState() {
    super.initState();
    _gestures = GestureCollector(viewportProvider: _resolvePointerViewport);
    _scrolls = ScrollCollector();

    SessionRecorder.engine.controller.onInterrupt(_dispatchPendingEvents);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SessionRecorder.engine.context.captureTree(false);
    });
  }

  @override
  void dispose() {
    _dispatchPendingEvents();
    _scrolls.dispose();
    final captureElement = _captureElement;
    if (captureElement != null) {
      TreeDetector.clearCaptureElement(captureElement);
      _captureElement = null;
    }
    SessionRecorder.engine.controller.onInterrupt(null);
    SessionRecorder.engine.controller.dispose();
    SessionRecorder.engine.context.dispose();
    super.dispose();
  }

  @override
  void onSessionSuspended() => _dispatchPendingEvents();

  void _dispatchPendingEvents() {
    _gestures.forceRecordCollector();
    _scrolls.forceRecordCollector();
  }

  Widget _captureBoundary(BuildContext context) {
    Element? resolvedElement;
    context.visitAncestorElements((ancestor) {
      if (ancestor is RenderObjectElement && ancestor.widget is Listener) {
        resolvedElement = ancestor;
      }
      return false;
    });

    final previous = _captureElement;
    final element = resolvedElement;

    if (element == null) {
      if (previous != null) TreeDetector.clearCaptureElement(previous);
      _captureElement = null;
      return widget.child;
    }

    if (!identical(previous, element)) {
      if (previous != null) TreeDetector.clearCaptureElement(previous);

      /// The recorder-owned Listener supplies one physical RenderObject anchor
      /// without depending on the client widget tree.
      _captureElement = element;
      TreeDetector.registerCaptureElement(element);
    }

    return widget.child;
  }

  Rect? _resolvePointerViewport() {
    final element = _captureElement;
    if (element == null || !element.mounted) return null;

    final view = View.maybeOf(element);
    if (view == null) return null;

    final devicePixelRatio = view.devicePixelRatio;
    final physicalWidth = view.physicalSize.width;
    final physicalHeight = view.physicalSize.height;

    if (!devicePixelRatio.isFinite ||
        devicePixelRatio <= 0 ||
        !physicalWidth.isFinite ||
        physicalWidth <= 0 ||
        !physicalHeight.isFinite ||
        physicalHeight <= 0) {
      return null;
    }

    final logicalWidth = physicalWidth / devicePixelRatio;
    final logicalHeight = physicalHeight / devicePixelRatio;
    if (!logicalWidth.isFinite ||
        logicalWidth <= 0 ||
        !logicalHeight.isFinite ||
        logicalHeight <= 0) {
      return null;
    }

    return Rect.fromLTWH(0, 0, logicalWidth, logicalHeight);
  }

  @override
  Widget build(BuildContext context) {
    Widget content = NotificationListener<ScrollNotification>(
      onNotification: _scrolls.handleScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _gestures.onPointerDown,
        onPointerMove: _gestures.onPointerMove,
        onPointerUp: _gestures.onPointerUp,
        onPointerCancel: _gestures.onPointerCancel,
        child: Builder(builder: _captureBoundary),
      ),
    );

    if (SessionRecorder.engine.config.debugShowTree) {
      final notifier = SessionRecorder.engine.context.notifier;
      if (notifier != null) {
        content = LomTreeOverlay(notifier: notifier, child: content);
      }
    }

    return content;
  }
}
