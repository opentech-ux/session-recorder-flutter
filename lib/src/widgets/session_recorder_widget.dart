import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/session_recorder.dart';

/// A wrapper widget that listens to user interactions across the app.
///
/// You should use [SessionRecorderWidget] as a wrapper to [WidgetsApp.builder].
///
/// The widget itself does not contain heavy logic; instead, it delegates
/// processing to internal services such as [InteractionDelegate] and
/// [SessionRecorder].
///
/// You can disable the widget layout painter by passing [false] to either
/// `showLayout`.
///
/// Also you can disable the capturing gestures data with `disable`
/// __only for testing__ purpose.
///
/// Example usage
/// ```dart
/// return MaterialApp(
///   navigatorKey: key,
///   builder: (context, child) => SessionRecorderWidget(
///     child: child ?? SizedBox.shrink(),
///   ),
/// );
/// ```
///
/// __IMPORTANT:__ This widget must be set **only once** in the entire app.
///
/// Adding multiple [SessionRecorderWidget] instances can lead to duplicated
/// event captures, inconsistent state, and performance degradation.
class SessionRecorderWidget extends StatelessWidget {
  const SessionRecorderWidget({
    super.key,
    required this.child,
    this.showLayout = false,
    this.disable = false,
  });

  final Widget child;
  final bool showLayout;
  final bool disable;

  @override
  Widget build(BuildContext context) {
    if (disable) return SizedBox.shrink();

    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: SessionRecorder.instance.onPointerDown,
          onPointerMove: SessionRecorder.instance.onPointerMove,
          onPointerUp: SessionRecorder.instance.onPointerUp,
          onPointerCancel: SessionRecorder.instance.onPointerCancel,
          child: NotificationListener<ScrollNotification>(
            onNotification: SessionRecorder.instance.handleScrollNotification,
            child: child,
          ),
        ),
        if (showLayout)
          ValueListenableBuilder<List<Rect>>(
            valueListenable: SessionRecorder.instance.rects,
            builder: (context, rects, child) {
              return IgnorePointer(
                ignoring: true,
                child: CustomPaint(
                  painter: _BoundsPainter(rects),
                  size: Size.infinite,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _BoundsPainter extends CustomPainter {
  final List<Rect> rects;

  _BoundsPainter(this.rects);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoundsPainter oldDelegate) {
    return oldDelegate.rects != rects;
  }
}
