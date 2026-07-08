import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/collectors/gestures_collector.dart';
import 'package:session_recorder_flutter/src/collectors/scroll_collector.dart';
import 'package:session_recorder_flutter/src/observers/session_lifecycle_observer.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_overlay.dart';

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

  @override
  void initState() {
    super.initState();
    _gestures = GestureCollector();
    _scrolls = ScrollCollector();

    SessionRecorder.engine.context.start();
    SessionRecorder.engine.controller.startReporting();
    SessionRecorder.engine.controller.onInterrupt(_dispatchPendingEvents);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyObserver();
    });
  }

  @override
  void dispose() {
    _dispatchPendingEvents();
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

  /// Verifies that at least one `[SessionNavigatorObserver]` is attached
  /// to a Navigator after the first frame.
  void _verifyObserver() {
    if (SessionRecorder.engine.controller.isNavigationAttached) return;

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'SessionNavigatorObserver was not attached to any Navigator.',
        ),
        library: 'session_recorder_flutter',
        context: ErrorDescription(
          'checking SessionNavigatorObserver attachment',
        ),
        informationCollector: () => <DiagnosticsNode>[
          ErrorDescription(
            'Pass the observer to MaterialApp.navigatorObservers:',
          ),
          ErrorHint(
            '  SessionRecorder.observer(\n'
            '    builder: (observer) => MaterialApp(\n'
            '      navigatorObservers: [observer],  // ← required\n'
            '      home: ...,\n'
            '    ),\n'
            '  );',
          ),
          ErrorDescription('\nOr if you are using GoRouter Navigator.'),
          ErrorDescription('Pass the observer to GoRouter.observers:'),
          ErrorHint(
            '  SessionRecorderWidget(\n'
            '    child: MaterialApp.router(\n'
            '      routeConfig: GoRouter(\n'
            '        observers: [SessionNavigatorObserver()], // ← required\n'
            '      ),\n'
            '      home: ...,\n'
            '    ),\n'
            '  );',
          ),
        ],
      ),
    );
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
        child: widget.child,
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
