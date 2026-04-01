import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/collectors/gestures_collector.dart';
import 'package:session_recorder_flutter/src/collectors/scroll_collector.dart';
import 'package:session_recorder_flutter/src/observers/session_lifecycle_observer.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_controller_internal.dart';
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
/// return SessionRecorder.observer(
///   builder: (observer) => MaterialApp(
///     navigatorObservers: [observer],
///     home: const HomeScreen(),
///   ),
/// );
/// ```
/// ### 2. No factory method
///
/// ```dart
/// return SessionRecorder(
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
    return SessionRecorderWidget(child: builder(observer));
  }

  @override
  State<SessionRecorderWidget> createState() => _SessionRecorderWidgetState();
}

class _SessionRecorderWidgetState extends State<SessionRecorderWidget>
    with WidgetsBindingObserver, SessionLifecycleObserver {
  late final GestureCollector _gestures;
  late final ScrollCollector _explorations;

  SessionRecorder get _session => SessionRecorder.instance;

  @override
  SessionControllerInternal get controller => _session.controller;

  @override
  void initState() {
    super.initState();
    _gestures = GestureCollector(_session.recorder);
    _explorations = ScrollCollector(_session.recorder);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyObserver();
    });
  }

  /// Verifies that at least one `[SessionNavigatorObserver]` is attached
  /// to a Navigator after the first frame.
  void _verifyObserver() {
    if (controller.isNavigationAttached) return;

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'SessionNavigatorObserver was not attached to any Navigator.\n'
          'Pass the observer to MaterialApp.navigatorObservers:\n\n'
          '  SessionRecorder.observer(\n'
          '    builder: (observer) => MaterialApp(\n'
          '      navigatorObservers: [observer],  // ← required\n'
          '      home: ...,\n'
          '    ),\n'
          '  );\n'
          'Or if you are using GoRouter Navigator.\n'
          'Pass the observer to GoRouter.observers:\n\n'
          '  SessionRecorderWidget(\n'
          '    child: MaterialApp.router(\n'
          '      routeConfig: GoRouter('
          '         observers: [SessionNavigatorObserver()]\n' // ← required\n'
          '      ),\n'
          '      home: ...,\n'
          '    ),\n'
          '  );\n',
        ),
        library: 'session_recorder_flutter',
        context: ErrorDescription(
          'checking SessionNavigatorObserver attachment',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = NotificationListener<ScrollNotification>(
      onNotification: _explorations.handleScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _gestures.onPointerDown,
        onPointerMove: _gestures.onPointerMove,
        onPointerUp: _gestures.onPointerUp,
        child: widget.child,
      ),
    );

    if (_session.config.debugShowTree) {
      final notifier = controller.notifier;
      if (notifier != null) {
        content = LomTreeOverlay(notifier: notifier, child: content);
      }
    }

    return content;
  }
}
