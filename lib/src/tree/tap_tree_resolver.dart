import 'package:flutter/rendering.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

class TapTreeResult {
  final Root? target;

  const TapTreeResult(this.target);

  bool get didTap => target != null;
}

typedef _Match = ({Root root, int depth});

class TapTreeFinder {
  const TapTreeFinder();

  TapTreeResult find(Lom lom, Offset position) {
    final paths = _getHitPaths(position);
    if (paths.isEmpty) return TapTreeResult(null);

    final hitsId = {
      for (int i = 0; i < paths.length; i++)
        paths[i].target.hashCode.toRadixString(16): i,
    };

    final match = _findDeepest(hitsId, [lom.root!]);

    if (match == null) {
      return TapTreeResult(null);
    }

    return TapTreeResult(match.root);
  }

  List<HitTestEntry> _getHitPaths(Offset position) {
    final HitTestResult hitTestResult = HitTestResult();
    final RenderView renderView = RendererBinding.instance.renderViews.first;

    RendererBinding.instance.hitTestInView(
      hitTestResult,
      position,
      renderView.flutterView.viewId,
    );

    return hitTestResult.path.toList();
  }

  _Match? _findDeepest(Map<String, int> hitsId, List<Root> roots) {
    _Match? found;

    for (Root root in roots) {
      final depth = hitsId[root.objectId];
      if (depth != null && (found == null || depth > found.depth)) {
        found = (root: root, depth: depth);
      }

      final foundChild = _findDeepest(hitsId, root.children);
      if (foundChild != null &&
          (found == null || foundChild.depth > foundChild.depth)) {
        found = foundChild;
      }
    }

    return found;
  }
}
