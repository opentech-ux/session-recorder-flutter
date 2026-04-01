import 'package:flutter/rendering.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

/// The result of resolving a tap position against a `[Lom]`.
class TapTreeResult {
  final Root? target;

  const TapTreeResult(this.target);

  bool get didTap => target != null;
}

typedef _DeepRoot = ({Root root, int depth});

/// Resolves a tap screen position to a `[Root]` in a `[Lom]`.
///
/// A single depth-first traversal finds the deepest matching root and its
/// ancestor path simultaneously.
class TapTreeFinder {
  const TapTreeFinder();

  /// Resolves `position` against `lom` and returns the deepest root.
  TapTreeResult find(LomAbstract lom, Offset position) {
    if (lom.root == null) return const TapTreeResult(null);

    final paths = _getHitPaths(position);
    if (paths.isEmpty) return const TapTreeResult(null);

    final hitsId = {
      for (int i = 0; i < paths.length; i++)
        if (paths[i].target case final RenderBox target
            when target.hasSize && target.size != Size.zero)
          target.hashCode.toRadixString(16): i,
    };

    final match = _findDeepest(hitsId, [lom.root!]);

    if (match == null) {
      return TapTreeResult(null);
    }

    return TapTreeResult(match.root);
  }

  /// Runs Flutter's own hit test and returns all entries in the hit path.
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

  /// Walks `roots` depth-first, returning the root with the lowest depth index.
  _DeepRoot? _findDeepest(
    Map<String, int> hitsId,
    List<Root> roots, {
    _DeepRoot? found,
  }) {
    for (Root root in roots) {
      if (found != null && found.depth == 0) return found;

      final depth = hitsId[root.objectId];

      if (depth != null && (found == null || depth < found.depth)) {
        found = (root: root, depth: depth);
      }

      found = _findDeepest(hitsId, root.children, found: found);
    }

    return found;
  }
}
