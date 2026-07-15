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

    final counter = _RootCounter();
    final children = _visitElement(
      element,
      config: _config,
      counter: counter,
      scrollOffset: Offset.zero,
    );

    final Rect? rect = MathUtils.transformRect(element.renderObject);

    if (rect == null) return null;

    final Root root = Root(
      id: counter.next(),
      objectId: element.renderObject.hashCode.toRadixString(16),
      widgetType: element.widget.runtimeType.toString(),
      renderType: element.renderObject.runtimeType.toString(),
      box: rect,
      children: children,
    );

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
    final contentSize = materializedContentSize(root);

    final Lom lom = Lom(
      id: lomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      width: contentSize.width.ceil(),
      height: contentSize.height.ceil(),
      root: root,
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
    required _RootCounter counter,
    required Offset scrollOffset,
  }) {
    final Widget widget = element.widget;

    final String widgetType = widget.runtimeType.toString();

    if (config.pruneAt.contains(widgetType)) return [];

    final renderObject = element.renderObject;
    final childScrollOffset = widget is RenderObjectWidget
        ? scrollOffset + _scrollOffsetOf(renderObject)
        : scrollOffset;

    final bool hasImportanteSemantic = config.semantics.contains(widgetType);

    if (widget is! RenderObjectWidget && !hasImportanteSemantic) {
      return _visitChildrenFlat(element, config, counter, childScrollOffset);
    }

    if (!hasImportanteSemantic && config.noiseAt.contains(widgetType)) {
      return _visitChildrenFlat(element, config, counter, childScrollOffset);
    }

    if (!hasImportanteSemantic &&
        (widgetType.startsWith('_') ||
            config.ignoreAt.any((w) => widgetType.contains(w)))) {
      return _visitChildrenFlat(element, config, counter, childScrollOffset);
    }

    final Rect? rect = MathUtils.transformRect(renderObject);

    if (rect == null || (rect.width == 0 && rect.height == 0)) {
      return _visitChildrenFlat(element, config, counter, childScrollOffset);
    }

    return [
      Root(
        id: counter.next(),
        objectId: renderObject.hashCode.toRadixString(16),
        widgetType: widgetType,
        renderType: renderObject.runtimeType.toString(),
        box: rect.shift(scrollOffset),
        children: _visitChildrenFlat(
          element,
          config,
          counter,
          childScrollOffset,
        ),
      ),
    ];
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
    _RootCounter counter,
    Offset scrollOffset,
  ) {
    final children = <Root>[];
    element.visitChildren((child) {
      final rootChildren = _visitElement(
        child,
        config: config,
        counter: counter,
        scrollOffset: scrollOffset,
      );
      if (rootChildren.isNotEmpty) {
        children.addAll(rootChildren);
      }
    });

    return children;
  }
}

class _RootCounter {
  int _value = 0;
  int next() => ++_value;
  void clear() => _value = 0;

  @override
  String toString() => "value: $_value";
}
