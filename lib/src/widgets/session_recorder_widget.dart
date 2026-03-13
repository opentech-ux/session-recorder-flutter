part of '../session_recorder_core.dart';

/// {@template session_recorder_widget}
/// A wrapper widget that listens to user interactions across the app.
///
/// You should use `[SessionRecorderWidget]` as a wrapper to `[WidgetsApp.builder]`.
///
/// The widget itself does not contain heavy logic; instead, it delegates
/// processing to internal services such as `[InteractionDelegate]` and
/// `[SessionRecorder]`.
///
/// You can disable the widget layout painter by passing `[false]` to either
/// `showLayout`.
///
/// Also you can disable the capturing gestures data with `disable`
/// __only for testing__ purpose.
///
/// Example usage
/// ```dart
/// return MaterialApp(
///   navigatorObservers: [
///     SessionRecorderObserver(),
///   ],
///   builder: (context, child) => SessionRecorderWidget(
///     child: child!,
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
  final bool showLayout;

  /// {@macro session_recorder_widget}
  const SessionRecorderWidget({
    super.key,
    required this.child,
    this.showLayout = false,
  });

  static Widget observer({
    Key? key,
    required Widget Function(SessionRecorderObserver observer) builder,
  }) {
    final observer = SessionRecorderObserver();
    return SessionRecorderWidget(child: builder(observer));
  }

  @override
  State<SessionRecorderWidget> createState() => _SessionRecorderWidgetState();
}

class _SessionRecorderWidgetState extends State<SessionRecorderWidget> {
  late final GestureCollector _gestures;
  late final ScrollCollector _explorations;
  late final SessionRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = SessionRecorder.instance;
    _gestures = GestureCollector(_recorder);
    _explorations = ScrollCollector(_recorder);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyObserver();
    });
  }

  ///
  void _verifyObserver() {
    if (_recorder.observer?.navigator != null) return;

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError(
          'SessionRecorderObserver was not attached to any Navigator.\n'
          'Pass the observer to MaterialApp.navigatorObservers:\n\n'
          '  SessionRecorder.wrapApp(\n'
          '    builder: (observer) => MaterialApp(\n'
          '      navigatorObservers: [observer],  // ← required\n'
          '      home: ...,\n'
          '    ),\n'
          '  );\n',
        ),
        library: 'session_recorder_flutter',
        context: ErrorDescription(
          'checking SessionRecorderObserver attachment',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _explorations.handleScrollNotification,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _gestures.onPointerDown,
            onPointerMove: _gestures.onPointerMove,
            onPointerUp: _gestures.onPointerUp,
            child: widget.child,
          ),
        ),

        // if (widget.showLayout)
        //   ValueListenableBuilder<List<Rect>>(
        //     valueListenable: SessionRecorder.instance.rects,
        //     builder: (context, rects, child) {
        //       return IgnorePointer(
        //         ignoring: true,
        //         child: CustomPaint(
        //           painter: _BoundsPainter(rects),
        //           size: Size.infinite,
        //         ),
        //       );
        //     },
        //   ),
      ],
    );
  }
}

// class _BoundsPainter extends CustomPainter {
//   final List<Rect> rects;

//   _BoundsPainter(this.rects);

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = Colors.red
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 1.5;

//     for (final rect in rects) {
//       canvas.drawRect(rect, paint);
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _BoundsPainter oldDelegate) {
//     return oldDelegate.rects != rects;
//   }
// }
