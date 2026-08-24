import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/collectors/gestures_collector.dart';
import 'package:session_recorder_flutter/src/collectors/scroll_collector.dart';
import 'package:session_recorder_flutter/src/observers/session_lifecycle_observer.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_overlay.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';

/// {@template session_recorder_widget}
/// Explicit boundary that activates behavior tracking for an application
/// subtree.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => SessionRecorderWidget(
///     child: child ?? const SizedBox.shrink(),
///   ),
/// );
/// ```
///
/// It installs the pointer and scroll collectors, provides the stable subtree
/// used by tree capture, and requests exactly one initial capture after the
/// first frame. Later captures caused by UI mutations remain managed by the
/// internal tree detector.
///
/// Installing it in `MaterialApp.builder` or `MaterialApp.router.builder` is
/// recommended so the captured subtree starts around the application's
/// Navigator or Router. Routes, overlays, dialogs, drawers, and modals remain
/// descendants. Wrapping `MaterialApp` externally is also supported and
/// captures a broader subtree.
///
/// This widget does not initialize or restart the engine, context, or
/// reporting. Call `SessionRecorder.init` before `runApp`.
///
/// Install this wrapper only once. [SessionNavigatorObserver] is optional and
/// is not required for the initial capture, gestures, scrolls, or ordinary UI
/// mutations.
/// {@endtemplate}
class SessionRecorderWidget extends StatefulWidget {
  final Widget child;

  /// Creates the capture boundary for [child].
  const SessionRecorderWidget({super.key, required this.child});

  /// Creates an optional [SessionNavigatorObserver] and exposes it to
  /// [builder] as a convenience for `MaterialApp.navigatorObservers`.
  ///
  /// ```dart
  /// SessionRecorderWidget.observer(
  ///   builder: (observer) => MaterialApp(
  ///     navigatorObservers: [observer],
  ///     home: const HomeScreen(),
  ///   ),
  /// );
  /// ```
  ///
  /// This factory is not required for initial capture, gestures, scrolls, or
  /// ordinary UI mutations. It preserves the supported outer-wrapper
  /// integration; applications using the recommended `MaterialApp.builder`
  /// integration can create and attach [SessionNavigatorObserver] separately.
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
      try {
        SessionLogger.verbose('LOM capture attempt reason=initial');
      } catch (_) {
        // Diagnostics cannot affect the client application.
      }
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
    final element = context as Element;
    final previous = _captureElement;

    if (!identical(previous, element)) {
      if (previous != null) TreeDetector.clearCaptureElement(previous);
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
