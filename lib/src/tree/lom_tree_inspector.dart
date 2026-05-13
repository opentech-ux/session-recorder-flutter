import 'package:flutter/material.dart';

import 'package:uuid/uuid.dart';

import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_hasher.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

/// Captures the visible widget tree as a list of [Root]s.
class LomTreeInspector {
  LomTreeInspector(SessionRecorderConfig config) {
    _config = const LomTreeConfig();
    _sessionRecorderConfig = config;
  }

  String _lastSignature = "";
  final Map<String, String> _cache = {};

  late LomTreeConfig _config;
  late SessionRecorderConfig _sessionRecorderConfig;

  /// Captures the widget tree starting from `[Element]`.
  LomAbstract? captureLom(Element? element) {
    if (element == null) return null;

    if (!element.mounted) return null;

    final counter = _RootCounter();
    final children = _visitElement(element, config: _config, counter: counter);

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

    if (_cache.containsKey(signature)) {
      final String cacheId = _cache[signature]!;

      return LomRef(
        id: cacheId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        root: (_sessionRecorderConfig.debugShowTree) ? root : null,
      );
    }

    final String lomId = Uuid().v7();

    final Lom lom = Lom(
      id: lomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      width: root.box.width.toInt(),
      height: root.box.height.toInt(),
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
    final Rect? rect = MathUtils.transformRect(renderObject);

    if (rect == null || (rect.width == 0 && rect.height == 0)) {
      return _visitChildrenFlat(element, config, counter);
    }

    return [
      Root(
        id: counter.next(),
        objectId: renderObject.hashCode.toRadixString(16),
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
}

class _RootCounter {
  int _value = 0;
  int next() => ++_value;
  void clear() => _value = 0;

  @override
  String toString() => "value: $_value";
}
