import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/collectors/gestures_collector.dart';
import 'package:session_recorder_flutter/src/collectors/scroll_collector.dart';
import 'package:session_recorder_flutter/src/observers/session_lifecycle_observer.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_overlay.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';

/// {@template session_recorder_widget}
/// Root widget that activates behavior tracking for the whole app.
///
/// You should use `[SessionRecorderWidget]` as a wrapper to `[MaterialApp]`.
///
/// The widget itself does not contain heavy logic; instead, it collects the
/// data to internal collectors such as `[GestureCollector]` and
/// `[ScrollCollector]`.
///
/// ## Setup — choose one based on your router
///
/// ### 1. Standard Flutter Navigator
///
/// Wrap the `[MaterialApp]` with the `.observer` method to has already the
/// `[SessionNavigatorObserver]` instance and pass it to `navigatorObservers`
/// ```dart
/// return SessionRecorderWidget.observer(
///   builder: (observer) => MaterialApp(
///     navigatorObservers: [observer],
///     home: const HomeScreen(),
///   ),
/// );
/// ```
/// ### 2. No factory method
///
/// ```dart
/// return SessionRecorderWidget(
///   child: MaterialApp(
///     navigatorObservers: [SessionNavigatorObserver()],
///     home: const HomeScreen(),
///   ),
/// );
/// ```
///
/// __IMPORTANT:__ This widget must be set **only once** in the entire app.
///
/// Adding multiple `[SessionRecorderWidget]` instances can lead to duplicated
/// event captures, inconsistent state, and performance degradation.
/// {@endtemplate}
class SessionRecorderWidget extends StatefulWidget {
  final Widget child;

  /// {@macro session_recorder_widget}
  const SessionRecorderWidget({super.key, required this.child});

  /// {@macro session_recorder_widget}
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
    _gestures = GestureCollector();
    _scrolls = ScrollCollector();

    SessionRecorder.engine.context.start();
    SessionRecorder.engine.controller.startReporting();
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
    final element = context as Element;
    final previous = _captureElement;

    if (!identical(previous, element)) {
      if (previous != null) TreeDetector.clearCaptureElement(previous);
      _captureElement = element;
      TreeDetector.registerCaptureElement(element);
    }

    return widget.child;
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
