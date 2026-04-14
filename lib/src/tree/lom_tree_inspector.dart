import 'package:flutter/material.dart';

import 'package:uuid/uuid.dart';

import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

/// Captures the visible widget tree as a list of [Root]s.
class LomTreeInspector {
  const LomTreeInspector._();

  static String _lastSignature = "";

  static final Map<String, String> _cache = {};

  /// Captures the widget tree starting from `[Element]`.
  static LomAbstract? captureLom(
    Element? element, {
    LomTreeConfig config = const LomTreeConfig(),
  }) {
    if (element == null) return null;

    if (!element.mounted) return null;

    final counter = _RootCounter();
    final children = _visitElement(element, config: config, counter: counter);

    final Rect? rect = _transformRect(element.renderObject);

    debugPrint("rect : ${rect.toString()}");

    if (rect == null) return null;

    final Root root = Root(
      id: counter.next(),
      objectId: element.renderObject.hashCode.toRadixString(16),
      parentId: 0,
      widgetType: element.widget.runtimeType.toString(),
      renderType: element.renderObject.runtimeType.toString(),
      box: rect,
      children: children,
    );

    debugPrint("root : ${root.toString()}");

    final signature = _signatureRoots([root]);

    if (_cache.containsKey(signature)) {
      debugPrint("EXIST ALREADY ??");
      debugPrint("${_cache.keys}");

      final String cacheId = _cache[signature]!;

      return LomRef(
        id: cacheId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        signature: signature,
        root: root,
      );
    }

    final String lomId = Uuid().v7();

    final Lom lom = Lom(
      id: lomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      width: root.box.width.toInt(),
      height: root.box.height.toInt(),
      signature: signature,
      root: root,
    );

    // If the stable structure did not change, no additional processing is
    // performed.
    if (signature == _lastSignature) return null;

    _cache[signature] = lomId;
    _lastSignature = signature;

    return lom;
  }

  static List<Root> _visitElement(
    Element element, {
    required LomTreeConfig config,
    required _RootCounter counter,
  }) {
    final Widget widget = element.widget;

    final String widgetType = widget.runtimeType.toString();

    if (config.pruneAt.contains(widgetType)) return [];

    if (config.noiseAt.contains(widgetType)) {
      return _visitChildrenFlat(element, config, counter);
    }

    final bool hasImportanteSemantic = config.semantics.contains(widgetType);

    if (widget is! RenderObjectWidget && !hasImportanteSemantic) {
      return _visitChildrenFlat(element, config, counter);
    }

    if (widgetType.startsWith('_') ||
        config.ignoreAt.any((w) => widgetType.contains(w))) {
      return _visitChildrenFlat(element, config, counter);
    }

    final renderObject = element.renderObject;
    final Rect? rect = _transformRect(renderObject);

    if (rect == null || (rect.width == 0 && rect.height == 0)) {
      return _visitChildrenFlat(element, config, counter);
    }

    return [
      Root(
        id: counter.next(),
        objectId: renderObject.hashCode.toRadixString(16),
        parentId: 0,
        widgetType: widgetType,
        renderType: renderObject.runtimeType.toString(),
        box: rect,
        children: _visitChildrenFlat(element, config, counter),
      ),
    ];
  }

  /// Visite children in flat mode using heavy spread to avoid unnecessary lists
  static List<Root> _visitChildrenFlat(
    Element element,
    LomTreeConfig config,
    _RootCounter counter,
  ) {
    final children = <Root>[];
    element.visitChildren((child) {
      final rootChildren = _visitElement(
        child,
        config: config,
        counter: counter,
      );
      if (rootChildren.isNotEmpty) {
        children.addAll(rootChildren);
      }
    });

    return children;
  }

  /// Computes the screen rect of `render` in global coordinates.
  static Rect? _transformRect(RenderObject? render) {
    if (render == null || !render.attached || render is! RenderBox) return null;
    try {
      final transform = render.getTransformTo(null);
      final Rect localRect = Offset.zero & render.size;
      return MatrixUtils.transformRect(transform, localRect);
    } catch (_) {
      return null;
    }
  }

  /// Signs into a hexadecimal every [Root] and its children.
  ///
  /// Example :
  /// ```bash
  ///   1847392847 => "9264b2f1"
  /// ```
  static String _signatureRoots(List<Root> roots) {
    final buffer = StringBuffer();
    for (var root in roots) {
      _writeRoot(root, buffer);
    }

    return buffer.toString().hashCode.toRadixString(16);
  }

  /// Bucketing the pixels to define 4 px tolerance
  ///
  /// Example :
  /// ```bash
  ///   "Scaffold0,0,97,211|AppBar0,10,97,14|..."
  /// ```
  static void _writeRoot(Root root, StringBuffer buffer) {
    final x = (root.box.topLeft.dx / 4).round();
    final y = (root.box.topLeft.dy / 4).round();
    final w = (root.box.width / 4).round();
    final h = (root.box.height / 4).round();
    buffer.write('${root.widgetType}$x,$y,$w,$h|');
    for (var child in root.children) {
      _writeRoot(child, buffer);
    }
  }
}

class _RootCounter {
  int _value = 0;
  int next() => ++_value;
  void clear() => _value = 0;

  @override
  String toString() => "value: $_value";
}
