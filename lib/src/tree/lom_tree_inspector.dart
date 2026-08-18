import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  String _lastSignature = "";
  final LinkedHashMap<String, String> _cache = LinkedHashMap();
  static const int _maxCachedSignatures = 4096;

  late LomTreeConfig _config;

  /// Captures the widget tree starting from `[Element]`.
  LomAbstract? captureLom(
    Element? element, {
    required bool comesFromNavigation,
  }) {
    if (element == null || !element.mounted) return null;

    try {
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
      // A child RenderObject has one real parent edge, so its cached value also
      // prevents that edge from being inspected more than once per capture.
      final effectiveClips = HashMap<RenderObject, Rect>.identity();
      final roots = _visitElement(
        element,
        viewport: viewport,
        effectiveClip: viewport,
        nearestRenderAncestor: null,
        effectiveClips: effectiveClips,
        config: _config,
        counter: counter,
      );

      if (roots.length != 1) {
        if (kDebugMode) {
          final widgetTypes = roots
              .map((root) => root.widgetType)
              .toList(growable: false);
          SessionLogger.warning(
            'LOM inspection skipped: expected '
            'exactly one top-level root, found ${roots.length}; '
            'top-level widgetTypes: $widgetTypes',
          );
        }
        return null;
      }
      final root = roots.single;

      final signature = LomTreeHasher.signatureRoots([root]);
      final isSameAsLast = signature == _lastSignature;

      if (isSameAsLast && !comesFromNavigation) {
        final cacheId = _findCachedLomId(signature);
        if (cacheId == null) return null;

        // Refresh local hit-test data without adding network noise.
        return LocalLomRef(
          id: cacheId,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          root: root,
        );
      }

      final cacheId = _findCachedLomId(signature);
      if (cacheId != null) {
        _lastSignature = signature;

        return LomRef(
          id: cacheId,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          root: root,
        );
      }

      final String lomId = Uuid().v7();

      final Lom lom = Lom(
        id: lomId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        width: viewportWidth.toInt(),
        height: viewportHeight.toInt(),
        root: root,
      );

      _rememberSignature(signature, lomId);
      _lastSignature = signature;

      return lom;
    } catch (_) {
      return null;
    }
  }

  /// Keeps signature cache bounded during long sessions.
  void _rememberSignature(String signature, String lomId) {
    if (_cache.containsKey(signature)) {
      _cache.remove(signature);
    } else if (_cache.length >= _maxCachedSignatures) {
      _cache.remove(_cache.keys.first);
    }

    _cache[signature] = lomId;
  }

  String? _findCachedLomId(String signature) {
    final lomId = _cache.remove(signature);
    if (lomId != null) _cache[signature] = lomId;
    return lomId;
  }

  static List<Root> _visitElement(
    Element element, {
    required Rect viewport,
    required Rect effectiveClip,
    required RenderObject? nearestRenderAncestor,
    required HashMap<RenderObject, Rect> effectiveClips,
    required LomTreeConfig config,
    required _RootCounter counter,
  }) {
    final Widget widget = element.widget;
    final String widgetType = widget.runtimeType.toString();
    var inheritedClip = effectiveClip;
    var inheritedRenderAncestor = nearestRenderAncestor;

    // Component elements may expose their first descendant RenderObject. Only
    // RenderObjectElement introduces a new edge in the render tree.
    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      inheritedClip = _resolveEffectiveClip(
        renderObject: renderObject,
        nearestRenderAncestor: nearestRenderAncestor,
        inheritedClip: effectiveClip,
        effectiveClips: effectiveClips,
      );
      inheritedRenderAncestor = renderObject;
    }

    if (inheritedClip.isEmpty) return [];

    if (config.pruneAt.contains(widgetType)) return [];

    final bool hasImportanteSemantic = config.semantics.contains(widgetType);

    if (widget is! RenderObjectWidget && !hasImportanteSemantic) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        config: config,
        counter: counter,
      );
    }

    if (!hasImportanteSemantic && config.noiseAt.contains(widgetType)) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        config: config,
        counter: counter,
      );
    }

    if (!hasImportanteSemantic &&
        (widgetType.startsWith('_') ||
            config.ignoreAt.any((w) => widgetType.contains(w)))) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        config: config,
        counter: counter,
      );
    }

    final renderObject = element.renderObject;
    final Rect? rect = MathUtils.transformRect(renderObject);

    if (rect == null || rect.width <= 0 || rect.height <= 0) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        config: config,
        counter: counter,
      );
    }

    final visibleRect = rect.intersect(inheritedClip).intersect(viewport);
    if (visibleRect.width <= 0 || visibleRect.height <= 0) {
      return _visitChildrenFlat(
        element,
        viewport: viewport,
        effectiveClip: inheritedClip,
        nearestRenderAncestor: inheritedRenderAncestor,
        effectiveClips: effectiveClips,
        config: config,
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
      config: config,
      counter: counter,
    );

    return [
      Root(
        id: id,
        objectId: renderObject.hashCode.toRadixString(16),
        widgetType: widgetType,
        renderType: renderObject.runtimeType.toString(),
        box: visibleRect,
        children: children,
      ),
    ];
  }

  /// Visite children in flat mode using heavy spread to avoid unnecessary lists
  static List<Root> _visitChildrenFlat(
    Element element, {
    required Rect viewport,
    required Rect effectiveClip,
    required RenderObject? nearestRenderAncestor,
    required HashMap<RenderObject, Rect> effectiveClips,
    required LomTreeConfig config,
    required _RootCounter counter,
  }) {
    final children = <Root>[];
    element.visitChildren((child) {
      final rootChildren = _visitElement(
        child,
        viewport: viewport,
        effectiveClip: effectiveClip,
        nearestRenderAncestor: nearestRenderAncestor,
        effectiveClips: effectiveClips,
        config: config,
        counter: counter,
      );
      if (rootChildren.isNotEmpty) {
        children.addAll(rootChildren);
      }
    });

    return children;
  }

  static Rect _resolveEffectiveClip({
    required RenderObject renderObject,
    required RenderObject? nearestRenderAncestor,
    required Rect inheritedClip,
    required HashMap<RenderObject, Rect> effectiveClips,
  }) {
    if (effectiveClips.containsKey(renderObject)) {
      return effectiveClips[renderObject]!;
    }

    if (nearestRenderAncestor == null) {
      effectiveClips[renderObject] = inheritedClip;
      return inheritedClip;
    }

    effectiveClips.putIfAbsent(nearestRenderAncestor, () => inheritedClip);

    // Stop at the first render ancestor already resolved. Any intermediate
    // RenderObjects are cached while unwinding, keeping the traversal linear.
    final chain = <RenderObject>[];
    var current = renderObject;

    while (!effectiveClips.containsKey(current)) {
      chain.add(current);
      final parent = current.parent;
      if (parent is! RenderObject) {
        effectiveClips[renderObject] = inheritedClip;
        return inheritedClip;
      }
      current = parent;
    }

    var resolvedClip = effectiveClips[current]!;

    for (final child in chain.reversed) {
      final parent = child.parent;
      if (parent is! RenderObject || !identical(parent, current)) {
        effectiveClips[renderObject] = inheritedClip;
        return inheritedClip;
      }

      final globalPaintClip = _globalPaintClip(parent, child);
      if (globalPaintClip != null) {
        final intersection = resolvedClip.intersect(globalPaintClip);
        resolvedClip = intersection.isEmpty ? Rect.zero : intersection;
      }

      effectiveClips[child] = resolvedClip;
      current = child;
    }

    return resolvedClip;
  }

  static Rect? _globalPaintClip(
    RenderObject parent,
    RenderObject child,
  ) {
    try {
      final localClip = parent.describeApproximatePaintClip(child);
      if (localClip == null || !_isFiniteRect(localClip)) return null;

      final transform = parent.getTransformTo(null);
      final globalClip = MatrixUtils.transformRect(transform, localClip);
      return _isFiniteRect(globalClip) ? globalClip : null;
    } catch (_) {
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

class _RootCounter {
  int _value = 0;
  int next() => ++_value;

  @override
  String toString() => "value: $_value";
}
