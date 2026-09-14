import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;
import 'package:session_recorder_flutter/src/session/session_logger.dart';

import 'package:uuid/uuid.dart';

import 'package:session_recorder_flutter/src/tree/lom_tree_hasher.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

/// Captures the visible widget tree as a list of [Root]s.
class LomTreeInspector {
  LomTreeInspector() {
    _config = const LomTreeConfig();
  }

  String _lastRef = "";
  final LinkedHashSet<String> _cache = LinkedHashSet();
  static const int _maxCachedSignatures = 4096;

  late LomTreeConfig _config;

  /// Captures the widget tree from its physical capture anchor [Element].
  LomAbstract? captureLom(
    Element? element, {
    required bool comesFromNavigation,
  }) {
    try {
      if (element == null || !element.mounted) return null;
      final view = View.maybeOf(element);
      if (view == null) return null;

      final devicePixelRatio = view.devicePixelRatio;
      final physicalSize = view.physicalSize;

      if (!devicePixelRatio.isFinite ||
          devicePixelRatio <= 0 ||
          !physicalSize.width.isFinite ||
          !physicalSize.height.isFinite ||
          physicalSize.width <= 0 ||
          physicalSize.height <= 0) {
        return null;
      }

      final viewportWidth = physicalSize.width / devicePixelRatio;
      final viewportHeight = physicalSize.height / devicePixelRatio;

      if (!viewportWidth.isFinite ||
          !viewportHeight.isFinite ||
          viewportWidth <= 0 ||
          viewportHeight <= 0) {
        return null;
      }

      final viewport = Rect.fromLTWH(0, 0, viewportWidth, viewportHeight);
      final counter = _RootCounter();
      final typeClassifications = <Type, _WidgetTypeClassification>{};

      /// Resolve each real parent edge only once per capture.
      final effectiveClips = HashMap<RenderObject, Rect>.identity();
      final paintEligibility = HashMap<RenderObject, bool>.identity();
      final roots = _visitElement(
        element,
        isCaptureAnchor: true,
        viewport: viewport,
        effectiveClip: viewport,
        nearestRenderAncestor: null,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: _config,
        typeClassifications: typeClassifications,
        counter: counter,
      );

      if (roots.length != 1) {
        if (kDebugMode) {
          SessionLogger.warning(
            'LOM inspection skipped: expected '
            'exactly one top-level root, found ${roots.length}',
          );
        }
        return null;
      }
      final root = roots.single;

      final ref = LomTreeHasher.signatureRoots([root]);
      final isSameAsLast = ref == _lastRef;

      if (_touchKnownRef(ref)) {
        _lastRef = ref;
        if (isSameAsLast && !comesFromNavigation) {
          // Refresh local state and overlay without a wire record.
          return LocalLomRef(
            ref: ref,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            root: root,
          );
        }
        return LomRef(
          ref: ref,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          root: root,
        );
      }

      final String lomId = Uuid().v7();

      final Lom lom = Lom(
        id: lomId,
        ref: ref,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        width: viewportWidth.toInt(),
        height: viewportHeight.toInt(),
        root: root,
      );

      _rememberRef(ref);
      _lastRef = ref;

      return lom;
    } catch (error) {
      SessionLogger.warning('LOM inspection failed with ${error.runtimeType}');

      return null;
    }
  }

  /// Keeps signature cache bounded during long sessions.
  void _rememberRef(String ref) {
    _cache.remove(ref);
    if (_cache.length >= _maxCachedSignatures) {
      _cache.remove(_cache.first);
    }
    _cache.add(ref);
  }

  bool _touchKnownRef(String ref) {
    if (!_cache.remove(ref)) return false;
    _cache.add(ref);
    return true;
  }

  static List<Root> _visitElement(
    Element element, {
    required bool isCaptureAnchor,
    required Rect viewport,
    required Rect effectiveClip,
    required RenderObject? nearestRenderAncestor,
    required HashMap<RenderObject, Rect> effectiveClips,
    required HashMap<RenderObject, bool> paintEligibility,
    required LomTreeConfig config,
    required Map<Type, _WidgetTypeClassification> typeClassifications,
    required _RootCounter counter,
  }) {
    if (isCaptureAnchor && element is! RenderObjectElement) return [];

    final Widget widget = element.widget;
    final type = widget.runtimeType;
    var classification = typeClassifications[type];
    if (classification == null) {
      classification = _WidgetTypeClassification(
        config.canonicalName(type) ?? type.toString(),
        type,
        widget,
        config,
      );
      typeClassifications[type] = classification;
    }
    final widgetType = classification.name;
    var inheritedClip = effectiveClip;
    var inheritedRenderAncestor = nearestRenderAncestor;

    /// Component elements may expose their first descendant RenderObject. Only
    /// RenderObjectElement introduces a new edge in the render tree.
    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      final resolvedClip = _resolveEffectiveClip(
        renderObject: renderObject,
        nearestRenderAncestor: nearestRenderAncestor,
        inheritedClip: effectiveClip,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
      );

      /// A definitive false means no descendant can paint through this edge.
      if (resolvedClip == null) return [];
      inheritedClip = resolvedClip;
      inheritedRenderAncestor = renderObject;
    }

    /// An empty ancestral clip forbids all descendant paint, so it safely
    /// prunes the entire geometric branch.
    if (inheritedClip.isEmpty) return [];

    /// Prune removes a subtree by policy; flattening below keeps descendants
    /// and propagates the same render ancestor and effective clip.
    if (!isCaptureAnchor && classification.prune) {
      return [];
    }

    final bool hasImportanteSemantic = classification.semantic;

    if (!isCaptureAnchor &&
        !classification.renderObjectWidget &&
        !hasImportanteSemantic) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: config,
        typeClassifications: typeClassifications,
        counter: counter,
      );
    }

    // Inspect the actual instance, not a component's descendant or a cached
    // Widget Type fact. Custom RenderStack subclasses keep their own policy.
    if (!isCaptureAnchor &&
        !hasImportanteSemantic &&
        (classification.noise ||
            (element is RenderObjectElement &&
                element.renderObject.runtimeType == RenderStack))) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: config,
        typeClassifications: typeClassifications,
        counter: counter,
      );
    }

    if (!isCaptureAnchor && !hasImportanteSemantic && classification.ignored) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: config,
        typeClassifications: typeClassifications,
        counter: counter,
      );
    }

    final renderObject = element.renderObject;
    final rect = MathUtils.transformRect(renderObject);

    /// Missing node geometry does not prune descendants because unclipped
    /// overflow may still paint outside the parent's own bounds.
    if (rect == null || rect.width <= 0 || rect.height <= 0) {
      if (isCaptureAnchor) return [];
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: config,
        typeClassifications: typeClassifications,
        counter: counter,
      );
    }

    final visibleRect = rect.intersect(inheritedClip).intersect(viewport);

    /// A Root needs visible geometry, but its children may still overflow when
    /// the inherited clip itself remains non-empty.
    /// Match Root.toMap() truncation so positive subpixel fragments do not
    /// become zero-sized wire boxes. Keep the original double geometry.
    if (visibleRect.width <= 0 ||
        visibleRect.height <= 0 ||
        visibleRect.width.toInt() <= 0 ||
        visibleRect.height.toInt() <= 0) {
      if (isCaptureAnchor) return [];
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: config,
        typeClassifications: typeClassifications,
        counter: counter,
      );
    }

    final id = counter.next();
    final children = _visitChildrenFlat(
      element,
      viewport: viewport,
      effectiveClip: inheritedClip,
      nearestRenderAncestor: inheritedRenderAncestor,
      effectiveClips: effectiveClips,
      paintEligibility: paintEligibility,
      config: config,
      typeClassifications: typeClassifications,
      counter: counter,
    );

    final roots = [
      Root(
        id: id,
        objectId: renderObject.hashCode.toRadixString(16),
        widgetType: widgetType,
        renderType: renderObject.runtimeType.toString(),
        box: visibleRect,
        children: children,
      ),
    ];
    return roots;
  }

  /// Visite children in flat mode using heavy spread to avoid unnecessary lists
  static List<Root> _visitChildrenFlat(
    Element element, {
    required Rect viewport,
    required Rect effectiveClip,
    required RenderObject? nearestRenderAncestor,
    required HashMap<RenderObject, Rect> effectiveClips,
    required HashMap<RenderObject, bool> paintEligibility,
    required LomTreeConfig config,
    required Map<Type, _WidgetTypeClassification> typeClassifications,
    required _RootCounter counter,
  }) {
    final children = <Root>[];
    // Traverse only children Flutter considers onstage so retained routes and
    // inactive branches do not become visible LOM nodes.
    element.debugVisitOnstageChildren((child) {
      final rootChildren = _visitElement(
        child,
        isCaptureAnchor: false,
        viewport: viewport,
        effectiveClip: effectiveClip,
        nearestRenderAncestor: nearestRenderAncestor,
        effectiveClips: effectiveClips,
        paintEligibility: paintEligibility,
        config: config,
        typeClassifications: typeClassifications,
        counter: counter,
      );
      if (rootChildren.isNotEmpty) {
        children.addAll(rootChildren);
      }
    });

    return children;
  }

  static Rect? _resolveEffectiveClip({
    required RenderObject renderObject,
    required RenderObject? nearestRenderAncestor,
    required Rect inheritedClip,
    required HashMap<RenderObject, Rect> effectiveClips,
    required HashMap<RenderObject, bool> paintEligibility,
  }) {
    if (paintEligibility[renderObject] == false) return null;

    if (effectiveClips.containsKey(renderObject)) {
      return effectiveClips[renderObject]!;
    }

    if (nearestRenderAncestor == null) {
      effectiveClips[renderObject] = inheritedClip;
      paintEligibility[renderObject] = true;
      return inheritedClip;
    }

    effectiveClips.putIfAbsent(nearestRenderAncestor, () => inheritedClip);
    paintEligibility.putIfAbsent(nearestRenderAncestor, () => true);

    // Stop at the first render ancestor already resolved. Any intermediate
    // RenderObjects are cached while unwinding, keeping the traversal linear.
    final chain = <RenderObject>[];
    var current = renderObject;

    while (!effectiveClips.containsKey(current) &&
        paintEligibility[current] != false) {
      chain.add(current);
      final parent = current.parent;
      if (parent is! RenderObject) {
        // Unknown render relationships remain visible to keep capture fail-open.
        effectiveClips[renderObject] = inheritedClip;
        paintEligibility[renderObject] = true;
        return inheritedClip;
      }
      current = parent;
    }

    if (paintEligibility[current] == false) {
      paintEligibility[renderObject] = false;
      return null;
    }

    var resolvedClip = effectiveClips[current]!;

    for (final child in chain.reversed) {
      final parent = child.parent;
      if (parent is! RenderObject || !identical(parent, current)) {
        // Unknown render relationships remain visible to keep capture fail-open.
        effectiveClips[renderObject] = inheritedClip;
        paintEligibility[renderObject] = true;
        return inheritedClip;
      }

      if (_paintsChild(parent, child) == false) {
        paintEligibility[child] = false;
        paintEligibility[renderObject] = false;
        return null;
      }

      final globalPaintClip = _globalPaintClip(parent, child);
      if (globalPaintClip != null) {
        /// Real paint clips accumulate as global rectangular bounds; no clip
        /// preserves Flutter's permitted overflow across the edge.
        final intersection = resolvedClip.intersect(globalPaintClip);
        resolvedClip = intersection.isEmpty ? Rect.zero : intersection;
      }

      effectiveClips[child] = resolvedClip;
      paintEligibility[child] = true;
      current = child;
    }

    return resolvedClip;
  }

  static bool? _paintsChild(RenderObject parent, RenderObject child) {
    try {
      return parent.paintsChild(child);
    } catch (_) {
      // Unknown paint participation remains visible to keep capture fail-open.
      return null;
    }
  }

  static Rect? _globalPaintClip(
    RenderObject parent,
    RenderObject child,
  ) {
    try {
      final localClip = parent.describeApproximatePaintClip(child);
      if (localClip == null || !_isFiniteRect(localClip)) return null;

      final Matrix4 transform = parent.getTransformTo(null);
      final globalClip = MatrixUtils.transformRect(transform, localClip);
      return _isFiniteRect(globalClip) ? globalClip : null;
    } catch (_) {
      /// Unsafe clip or transform data must not hide content the inspector
      /// cannot prove Flutter excludes from paint.
      return null;
    }
  }

  static bool _isFiniteRect(Rect rect) {
    return rect.left.isFinite &&
        rect.top.isFinite &&
        rect.right.isFinite &&
        rect.bottom.isFinite;
  }
}

/// Immutable type facts only; instances and capture-anchor policy stay uncached.
class _WidgetTypeClassification {
  final String name;
  final bool prune;
  final bool semantic;
  final bool renderObjectWidget;
  final bool noise;
  final bool ignored;

  _WidgetTypeClassification(
    this.name,
    Type type,
    Widget widget,
    LomTreeConfig config,
  )   : prune = config.pruneAt.containsKey(type),
        semantic = config.semantics.containsKey(type),
        renderObjectWidget = widget is RenderObjectWidget,
        noise = config.noiseAt.containsKey(type),
        ignored = LomTreeConfig.ignoredTypes.containsKey(type) ||
            name.startsWith('_') ||
            config.ignoreAt.any((pattern) => name.contains(pattern));
}

class _RootCounter {
  int _value = 0;
  int next() => ++_value;

  @override
  String toString() => "value: $_value";
}
