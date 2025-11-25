import 'package:session_recorder_flutter/src/utils/serialize_tree_utils.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/widgets_excluded_constants.dart';
import 'package:session_recorder_flutter/src/services/session_recorder.dart';

import '../models/models.dart' show Lom, Root, LomAbstract, LomRef;

class LomNotInitializedException implements Exception {
  final String message;
  LomNotInitializedException([this.message = 'Lom not initialized']);
  @override
  String toString() => 'LomNotInitializedException: $message';
}

/// {@template interaction_delegate}
/// A delegate responsible for managing and processing the [Widget] tree.
///
/// The [LomDelegate] manages the entire search of the widget tree and
/// converts it into instances of [Root], finally putting everything into
/// a [Lom].
///
/// Typically initialized internally by [SessionRecorder] and managed
/// in [InteractionDelegate].
/// {@endtemplate}
class LomDelegate {
  static final LomDelegate _instance = LomDelegate._internal();
  factory LomDelegate() => _instance;
  LomDelegate._internal();

  Lom? _lom;

  Lom get lom {
    final lom = _lom;
    if (lom == null) throw LomNotInitializedException();
    return lom;
  }

  /// Stack cache that stores the most recent [Lom].
  final Map<String, Lom> _cacheLom = {};

  /// Clears the cache [Lom] objects
  void clearCache() => _cacheLom.clear();

  /// Unique identifier [Root] node
  int _zoneId = 1;

  /// Tracks the [Root] nodes by its [HashCode]
  final Map<int, Root> rootReference = <int, Root>{};

  /// Clears the `_lom`
  void clearLom() => _lom = null;

  /// Creates and assigns a new [Lom] instance using a given `size` viewport.
  void _init(Size size) {
    _lom = Lom(
      id: Uuid().v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      width: size.width.toInt(),
      height: size.height.toInt(),
    );
  }

  void recursiveBox(Root root, List<Rect> output) {
    output.add(root.box);
    for (var child in root.children) {
      recursiveBox(child, output);
    }
  }

  /// Builds and returns a [Lom] tree bases on the widget hierarchy
  /// starting from the given `element`.
  ///
  /// This methods is the most important cause the [Element] recursively visits
  /// its child elements, creating a [Root] node for each one and storing them
  /// in the `rootReference` map with their `hashCode` key.
  ///
  /// Avoid rebuilding the Widget tree if the signature already exists in the cache.
  /// Instead, insert a [LomRef] that references the existing [Lom] instance.
  /// Improves performance and prevents data duplication.
  LomAbstract? createLomTree(Element element, String signature) {
    try {
      if (!element.mounted) return null;

      if (_cacheLom.keys.contains(signature)) {
        final Lom lomFound = _cacheLom[signature]!;

        final output = <Rect>[];
        recursiveBox(lomFound.root!, output);

        SessionRecorder().rects.value = List.unmodifiable(output);

        return LomRef(
          id: lomFound.id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
      }

      if (rootReference.isNotEmpty) rootReference.clear();

      final RenderObject? rootRenderObject = element.renderObject;

      if (rootRenderObject == null) return null;
      if (!rootRenderObject.attached) return null;
      if (rootRenderObject is! RenderBox) return null;

      final RenderBox renderBox = rootRenderObject;
      final Size rootSize = renderBox.size;

      if (rootSize.width == 0 && rootSize.height == 0) return null;

      _init(rootSize);

      /// Resets the count zones
      _zoneId = 1;

      final Offset rootOffset = renderBox.localToGlobal(Offset.zero);

      /// First [Root] node
      final Root root = _createRootFromElement(
        widgetType: element.widget.runtimeType.toString(),
        renderObject: rootRenderObject,
        box: Rect.fromLTWH(
          rootOffset.dx,
          rootOffset.dy,
          rootSize.width,
          rootSize.height,
        ),
      );

      rootReference[root.objectId] = root;

      /// Recursively elements
      element.visitChildElements((child) => _mapRootTree(child));

      /// Re-create a new map based by `rootReference` but with their `children`
      final Map<int, Root> rootMap = {
        for (final root in rootReference.values)
          root.id: root.copyWith(children: List<Root>.from(root.children)),
      };

      /// Delete the first [Root] to avoid duplication of the first same [Root]
      /// We gonna already used it in `_mapRootTree` and it is set it after
      /// in the `_lom`
      rootMap.remove(root.id);

      final Set<Root> rootsAttached = {};

      /// Attach every [Root] node that corresponds their `parentId`
      for (final root in rootMap.values) {
        final int parentId = root.parentId;

        if (parentId == root.id || !rootMap.containsKey(parentId)) {
          rootsAttached.add(root);
        } else {
          rootMap[parentId]!.children.add(root);
        }
      }

      _lom = _lom!.copyWith(
        root: root.copyWith(children: rootsAttached.toList()),
      );

      final output = <Rect>[];
      recursiveBox(_lom!.root!, output);
      SessionRecorder().rects.value = List.unmodifiable(output);

      _cacheLom[signature] = _lom!;

      return _lom;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return null;
    }
  }

  /// Recursively maps the `element` tree widgets into a [Root] instance.
  ///
  /// This method inspects every [Element]'s child and it meets the configured
  /// criteria __(e.g., has a valid [RenderBox], `shouldInclude()` method, ect)__,
  /// it creates a corresponding [Root] node.
  ///
  /// Then, it calls itself on each child element to continue building the tree
  /// from top to bottom, but also finds its ancestor [Element] to add its
  /// hashCode id.
  void _mapRootTree(Element element) {
    try {
      final Widget widgetElement = element.widget;

      final RenderObject? renderObject = element.renderObject;

      if (renderObject == null) {
        element.visitChildren((child) => _mapRootTree(child));
        return;
      }

      if (widgetElement is RenderObjectWidget && renderObject is RenderBox) {
        if (_shouldInclude(widgetElement, renderObject)) {
          if (SerializeTreeUtils.isWidgetVisible(element)) {
            final Offset offset = renderObject.localToGlobal(Offset.zero);
            final Rect rect = Rect.fromLTWH(
              offset.dx,
              offset.dy,
              renderObject.size.width,
              renderObject.size.height,
            );

            Root root = _createRootFromElement(
              widgetType: widgetElement.runtimeType.toString(),
              renderObject: renderObject,
              box: rect,
            );

            /// Visit `element`'s ancestor to set the `parentId` attribute
            if (element.mounted) {
              element.visitAncestorElements((parent) {
                final RenderObject? parentRender = parent.renderObject;
                if (parentRender == null) return true;

                final parentNode = rootReference[parentRender.hashCode];
                if (parentNode == null) return true;

                root = root.copyWith(parentId: parentNode.id);

                return false;
              });
            }

            rootReference[root.objectId] = root;
          }
        }
      }
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return;
    }

    element.visitChildren((child) => _mapRootTree(child));
  }

  /// Creates a [Root] object from the `renderObject`.
  Root _createRootFromElement({
    required String widgetType,
    required RenderObject renderObject,
    required Rect box,
  }) => Root(
    id: _zoneId++,
    objectId: renderObject.hashCode,
    parentId: 0,
    widgetType: widgetType,
    renderType: renderObject.runtimeType.toString(),
    box: box,
    children: [],
  );

  /// Determines whether a [Widget] should be included in the [Root] tree mapping.
  ///
  /// This method applies filtering rules to skip irrelevant or non-visual widgets.
  /// It checks multiple conditions such as:
  /// - The widget type (e.g., excludes internal/private widgets starting with `_`)
  /// - The presence of a valid [RenderBox] with a measurable size
  /// - Any additional criteria defined for visibility or interaction relevance
  ///
  /// Returns [true] if the widget is considered valid and should be part of the
  /// mapped tree; otherwise, returns [false].
  bool _shouldInclude(Widget widget, RenderBox renderBox) {
    final String widgetType = widget.runtimeType.toString();

    if (!renderBox.hasSize || renderBox.size == Size.zero) return false;

    if (widgetsToIgnore.contains(widgetType)) return false;

    for (final widget in widgetsToIgnoreIfContains) {
      if (widgetType.contains(widget)) return false;
    }

    if (widgetType.startsWith('_')) return false;

    return true;
  }
}
