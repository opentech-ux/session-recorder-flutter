import 'package:flutter/widgets.dart';

import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

/// Debug overlay that paints `[Root]` bounding boxes on top of the app.
///
/// Only renders in debug builds (`[kDebugMode]`). Each node is drawn as a
/// semi-transparent colored rectangle. Leaf nodes (no children) are painted
/// in green to highlight interactive widgets; containers are painted in blue.
///
/// Enable via `[SessionRecorderConfig.debugShowTree]`.
class LomTreeOverlay extends StatelessWidget {
  final Widget child;

  /// Receives `[LomAbstract]` to paint.
  final ValueListenable<LomAbstract?> notifier;

  const LomTreeOverlay({
    super.key,
    required this.notifier,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;

    return ValueListenableBuilder(
      valueListenable: notifier,
      builder: (context, lom, _) {
        if (lom == null) return child;
        final root = lom.root;
        if (root == null) return child;

        return Stack(
          alignment: Alignment.topLeft,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _TreePainter([root])),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TreePainter extends CustomPainter {
  final List<Root> roots;

  _TreePainter(this.roots);

  static final _containerPaint = Paint()
    ..color = const Color.fromARGB(139, 243, 33, 33)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final node in roots) {
      _paintNode(canvas, node);
    }
  }

  void _paintNode(Canvas canvas, Root node) {
    final rect = node.box;

    canvas.drawRect(rect, _containerPaint);

    for (final child in node.children) {
      _paintNode(canvas, child);
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) => old.roots != roots;
}
