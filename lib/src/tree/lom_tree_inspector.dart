import 'dart:collection';

import 'package:flutter/material.dart';

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

      final viewport = Rect.fromLTWH(
        0,
        0,
        viewportWidth,
        viewportHeight,
      );
      final counter = _RootCounter();
      final roots = _visitElement(
        element,
        viewport: viewport,
        config: _config,
        counter: counter,
      );

      if (roots.length != 1) return null;
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
    required LomTreeConfig config,
    required _RootCounter counter,
  }) {
    final Widget widget = element.widget;

    final String widgetType = widget.runtimeType.toString();

    if (config.pruneAt.contains(widgetType)) return [];

    final bool hasImportanteSemantic = config.semantics.contains(widgetType);

    if (widget is! RenderObjectWidget && !hasImportanteSemantic) {
      return _visitChildrenFlat(element, viewport, config, counter);
    }

    if (!hasImportanteSemantic && config.noiseAt.contains(widgetType)) {
      return _visitChildrenFlat(element, viewport, config, counter);
    }

    if (!hasImportanteSemantic &&
        (widgetType.startsWith('_') ||
            config.ignoreAt.any((w) => widgetType.contains(w)))) {
      return _visitChildrenFlat(element, viewport, config, counter);
    }

    final renderObject = element.renderObject;
    final Rect? rect = MathUtils.transformRect(renderObject);

    if (rect == null || rect.width <= 0 || rect.height <= 0) {
      return _visitChildrenFlat(element, viewport, config, counter);
    }

    final visibleRect = rect.intersect(viewport);
    if (visibleRect.width <= 0 || visibleRect.height <= 0) {
      return _visitChildrenFlat(element, viewport, config, counter);
    }

    final id = counter.next();
    final children = _visitChildrenFlat(element, viewport, config, counter);

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
    Element element,
    Rect viewport,
    LomTreeConfig config,
    _RootCounter counter,
  ) {
    final children = <Root>[];
    element.visitChildren((child) {
      final rootChildren = _visitElement(
        child,
        viewport: viewport,
        config: config,
        counter: counter,
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
