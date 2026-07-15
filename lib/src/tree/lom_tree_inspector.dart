import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

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
    if (element == null) return null;

    if (!element.mounted) return null;

    final Rect? rect = MathUtils.transformRect(element.renderObject);

    if (rect == null) return null;

    // Locate the main scroll before building content coordinates.
    final primaryViewport = _findPrimaryViewport(element, rect, _config);
    final capture = _CaptureState();
    final children = _visitElement(
      element,
      config: _config,
      capture: capture,
      primaryViewport: primaryViewport?.renderObject,
      insidePrimaryViewport: false,
      scrollOffset: Offset.zero,
    );

    final Root root = Root(
      id: capture.nextId(),
      objectId: element.renderObject.hashCode.toRadixString(16),
      widgetType: element.widget.runtimeType.toString(),
      renderType: element.renderObject.runtimeType.toString(),
      box: rect,
      children: children,
      coordinateSpace: _coordinateSpace(false, children),
    );
    final viewportOffset = primaryViewport?.offset ?? Offset.zero;

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
        viewportOffset: viewportOffset,
      );
    }

    final cacheId = _findCachedLomId(signature);
    if (cacheId != null) {
      _lastSignature = signature;

      return LomRef(
        id: cacheId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        root: root,
        viewportOffset: viewportOffset,
      );
    }

    final String lomId = Uuid().v7();
    final contentSize = materializedContentSize(root);

    final Lom lom = Lom(
      id: lomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      width: contentSize.width.ceil(),
      height: contentSize.height.ceil(),
      root: root,
      viewportOffset: viewportOffset,
    );

    _rememberSignature(signature, lomId);
    _lastSignature = signature;

    return lom;
  }

  /// Measures the full extent of the render objects Flutter has materialized.
  ///
  /// Eager scrollables such as a `SingleChildScrollView` usually expose their
  /// off-screen children, so the resulting size can exceed the route viewport.
  /// Lazy slivers only contribute the children that currently exist.
  @visibleForTesting
  static Size materializedContentSize(Root root) {
    var maxRight = root.box.right;
    var maxBottom = root.box.bottom;

    void visit(Root node) {
      if (node.box.right.isFinite && node.box.right > maxRight) {
        maxRight = node.box.right;
      }
      if (node.box.bottom.isFinite && node.box.bottom > maxBottom) {
        maxBottom = node.box.bottom;
      }

      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);

    return Size(
      maxRight < root.box.width ? root.box.width : maxRight,
      maxBottom < root.box.height ? root.box.height : maxBottom,
    );
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
    required LomTreeConfig config,
    required _CaptureState capture,
    required RenderObject? primaryViewport,
    required bool insidePrimaryViewport,
    required Offset scrollOffset,
  }) {
    // Propagate only the main viewport offset through content coordinates.
    final Widget widget = element.widget;

    final String widgetType = widget.runtimeType.toString();

    if (widget is Offstage && widget.offstage) return [];
    if (config.pruneAt.contains(widgetType)) return [];

    final renderObject = element.renderObject;
    final isPrimaryViewport =
        widget is RenderObjectWidget &&
        identical(renderObject, primaryViewport);
    final ownScrollOffset = isPrimaryViewport
        ? _scrollOffsetOf(renderObject)
        : Offset.zero;

    final childScrollOffset = scrollOffset + ownScrollOffset;
    final childInsidePrimaryViewport =
        insidePrimaryViewport || isPrimaryViewport;

    final bool hasImportanteSemantic = config.semantics.contains(widgetType);

    if (widget is! RenderObjectWidget && !hasImportanteSemantic) {
      return _visitChildrenFlat(
        element,
        config,
        capture,
        primaryViewport,
        childInsidePrimaryViewport,
        childScrollOffset,
      );
    }

    if (!hasImportanteSemantic && config.noiseAt.contains(widgetType)) {
      return _visitChildrenFlat(
        element,
        config,
        capture,
        primaryViewport,
        childInsidePrimaryViewport,
        childScrollOffset,
      );
    }

    if (!hasImportanteSemantic &&
        (widgetType.startsWith('_') ||
            config.ignoreAt.any((w) => widgetType.contains(w)))) {
      return _visitChildrenFlat(
        element,
        config,
        capture,
        primaryViewport,
        childInsidePrimaryViewport,
        childScrollOffset,
      );
    }

    final Rect? rect = MathUtils.transformRect(renderObject);

    if (rect == null || (rect.width == 0 && rect.height == 0)) {
      return _visitChildrenFlat(
        element,
        config,
        capture,
        primaryViewport,
        childInsidePrimaryViewport,
        childScrollOffset,
      );
    }

    final children = _visitChildrenFlat(
      element,
      config,
      capture,
      primaryViewport,
      childInsidePrimaryViewport,
      childScrollOffset,
    );

    return [
      Root(
        id: capture.nextId(),
        objectId: renderObject.hashCode.toRadixString(16),
        widgetType: widgetType,
        renderType: renderObject.runtimeType.toString(),
        box: rect.shift(scrollOffset),
        children: children,
        coordinateSpace: _coordinateSpace(insidePrimaryViewport, children),
      ),
    ];
  }

  static _PrimaryViewport? _findPrimaryViewport(
    Element element,
    Rect rootBox,
    LomTreeConfig config,
  ) {
    // The largest visible viewport represents the route's main scroll.
    _PrimaryViewport? primary;
    var largestVisibleArea = -1.0;
    final rootArea = rootBox.width * rootBox.height;

    void visit(
      Element current,
      Offset parentScrollOffset,
      Axis? pendingPagerAxis,
    ) {
      final widget = current.widget;
      final widgetType = widget.runtimeType.toString();
      if (widget is Offstage && widget.offstage) return;
      if (config.pruneAt.contains(widgetType)) return;

      final renderObject = current.renderObject;
      final pagerAxis = _localPagerAxis(widget) ?? pendingPagerAxis;
      final viewportAxis = _viewportAxisOf(renderObject);
      final isPagerViewport = pagerAxis != null && viewportAxis == pagerAxis;
      final ownScrollOffset = widget is RenderObjectWidget && !isPagerViewport
          ? _scrollOffsetOf(renderObject)
          : Offset.zero;
      final cumulativeScrollOffset = parentScrollOffset + ownScrollOffset;

      if (widget is RenderObjectWidget &&
          renderObject is RenderAbstractViewport &&
          !isPagerViewport) {
        final viewportRect = MathUtils.transformRect(renderObject);
        if (viewportRect != null) {
          final visible = viewportRect.intersect(rootBox);
          final visibleArea = visible.isEmpty
              ? 0.0
              : visible.width * visible.height;

          if (visibleArea > largestVisibleArea) {
            largestVisibleArea = visibleArea;
            primary = _PrimaryViewport(
              renderObject: renderObject,
              offset: cumulativeScrollOffset,
            );
          }
        }
      }

      final childPagerAxis = isPagerViewport ? null : pagerAxis;
      current.visitChildren(
        (child) => visit(child, cumulativeScrollOffset, childPagerAxis),
      );
    }

    visit(element, Offset.zero, null);
    return largestVisibleArea >= rootArea * 0.5 ? primary : null;
  }

  static Axis? _localPagerAxis(Widget widget) {
    if (widget is PageView) return widget.scrollDirection;
    if (widget is TabBarView || widget is CarouselView) {
      return Axis.horizontal;
    }
    return null;
  }

  static Axis? _viewportAxisOf(RenderObject? renderObject) {
    if (renderObject is! RenderAbstractViewport) return null;

    try {
      final dynamic viewport = renderObject;
      return switch (viewport.axisDirection as AxisDirection) {
        AxisDirection.up || AxisDirection.down => Axis.vertical,
        AxisDirection.left || AxisDirection.right => Axis.horizontal,
      };
    } catch (_) {
      return null;
    }
  }

  static LomCoordinateSpace _coordinateSpace(
    bool insidePrimaryViewport,
    List<Root> children,
  ) {
    // Outside the viewport, only ancestors joining both layers are mixed.
    if (insidePrimaryViewport) return LomCoordinateSpace.content;

    return children.any(
          (child) => child.coordinateSpace != LomCoordinateSpace.screen,
        )
        ? LomCoordinateSpace.mixed
        : LomCoordinateSpace.screen;
  }

  static Offset _scrollOffsetOf(RenderObject? renderObject) {
    if (renderObject is! RenderAbstractViewport) return Offset.zero;

    try {
      // SingleChildScrollView uses a private RenderAbstractViewport class,
      // but its axisDirection and offset getters are public.
      final dynamic viewport = renderObject;

      return viewportContentOffset(
        viewport.axisDirection as AxisDirection,
        viewport.offset.pixels as double,
      );
    } catch (_) {
      return Offset.zero;
    }
  }

  @visibleForTesting
  static Offset viewportContentOffset(
    AxisDirection axisDirection,
    double pixels,
  ) {
    return switch (axisDirection) {
      AxisDirection.down => Offset(0, pixels),
      AxisDirection.up => Offset(0, -pixels),
      AxisDirection.right => Offset(pixels, 0),
      AxisDirection.left => Offset(-pixels, 0),
    };
  }

  /// Visite children in flat mode using heavy spread to avoid unnecessary lists
  static List<Root> _visitChildrenFlat(
    Element element,
    LomTreeConfig config,
    _CaptureState capture,
    RenderObject? primaryViewport,
    bool insidePrimaryViewport,
    Offset scrollOffset,
  ) {
    final children = <Root>[];
    element.visitChildren((child) {
      final rootChildren = _visitElement(
        child,
        config: config,
        capture: capture,
        primaryViewport: primaryViewport,
        insidePrimaryViewport: insidePrimaryViewport,
        scrollOffset: scrollOffset,
      );
      if (rootChildren.isNotEmpty) {
        children.addAll(rootChildren);
      }
    });

    return children;
  }
}

class _CaptureState {
  int _value = 0;

  int nextId() => ++_value;

  void clear() => _value = 0;

  @override
  String toString() => "value: $_value";
}

class _PrimaryViewport {
  final RenderObject renderObject;
  final Offset offset;

  const _PrimaryViewport({required this.renderObject, required this.offset});
}
