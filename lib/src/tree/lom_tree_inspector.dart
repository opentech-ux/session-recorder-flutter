import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:uuid/uuid.dart';

/// Captures the visible widget tree as a list of [Root]s.
class LomTreeInspector {
  const LomTreeInspector._();

  static final LinkedHashMap<String, Lom> _cache = LinkedHashMap();

  /// Captures the widget tree starting from `[Element]`.
  static LomAbstract? captureLom(
    Element? element, {
    LomTreeConfig config = const LomTreeConfig(),
  }) {
    final rootElement = element ?? WidgetsBinding.instance.rootElement;
    debugPrint('rootElement.runtimeType');
    debugPrint(rootElement.runtimeType.toString());
    if (rootElement == null) return null;

    final counter = _RootCounter();
    final children = _visitElement(
      rootElement,
      config: config,
      counter: counter,
    );

    final Rect? rect = _transformRect(rootElement.renderObject);

    if (rect == null) return null;

    final Root root = Root(
      id: counter.next(),
      objectId: rootElement.renderObject.hashCode.toRadixString(16),
      parentId: 0,
      widgetType: rootElement.widget.runtimeType.toString(),
      renderType: rootElement.renderObject.runtimeType.toString(),
      box: rect,
      children: children,
    );

    // _printTree(children, 0);

    final signature = _signatureRoots([root]);

    debugPrint("signature");
    debugPrint(signature.toString());

    if (_cache.containsKey(signature)) {
      final Lom cacheLom = _cache[signature]!;

      return LomRef(
        id: cacheLom.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        signature: cacheLom.signature,
        root: cacheLom.root,
      );
    }

    final Lom lom = Lom(
      id: Uuid().v7(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      width: root.box.width.toInt(),
      height: root.box.height.toInt(),
      signature: signature,
      root: root,
    );

    _cache[signature] = lom;

    return lom;
  }

  // static void _printTree(List<Root> nodes, int indent) {
  //   for (final node in nodes) {
  //     debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
  //     _printTree(node.children, indent + 1);
  //   }
  // }

  static List<Root> _visitElement(
    Element element, {
    required LomTreeConfig config,
    required _RootCounter counter,
  }) {
    final Widget widget = element.widget;
    final String widgetType = widget.runtimeType.toString();

    // Always visit children first, even skipped roots may have valid children.
    final children = <Root>[];
    element.visitChildren((child) {
      children.addAll(_visitElement(child, config: config, counter: counter));
    });

    // Only capture RenderObjectWidgets, skips all StatelessWidget wrappers.
    if (widget is! RenderObjectWidget) return children;

    if (widgetType.startsWith('_')) return children;

    if (config.pruneAt.contains(widgetType)) return children;
    if (config.ignoreAt.any((widget) => widgetType.contains(widget))) {
      return children;
    }

    final renderObject = element.renderObject;
    final Rect? rect = _transformRect(renderObject);

    if (rect == null || (rect.width == 0 && rect.height == 0)) {
      return children;
    }

    return [
      Root(
        id: counter.next(),
        objectId: renderObject.hashCode.toRadixString(16),
        parentId: 0,
        widgetType: widgetType,
        renderType: renderObject.runtimeType.toString(),
        box: rect,
        children: children,
      ),
    ];
  }

  /// Computes the screen rect of `render` in global coordinates.
  static Rect? _transformRect(RenderObject? render) {
    if (render == null || !render.attached || render is! RenderBox) return null;
    try {
      final transform = render.getTransformTo(render);
      final Offset position = render.localToGlobal(Offset.zero);
      return MatrixUtils.transformRect(transform, position & render.size);
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
}
