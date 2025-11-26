import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Top-level compute hash
String _computeBufferHash(String buffer) => buffer.hashCode.toString();

/// Class responsible for serializing (signing) the tree of Elements
/// and calculating a hash of that signature in an isolate.
class SerializeTreeUtils {
  /// Serialize the `root` tree in a [String] that represents a
  /// "Signature Stable"
  static String _serializeTree(Element root) {
    final StringBuffer bufferTree = StringBuffer();
    _buildElementTreeBuffer(root, bufferTree);
    return bufferTree.toString();
  }

  /// Runs expensive processing in a separate isolate to avoid blocking the
  /// main (UI) thread.
  static Future<String> _hashSignature(String bufferTree) =>
      compute(_computeBufferHash, bufferTree.toString());

  /// Main `root` tree capture processor that returns a hash signature [String]
  static Future<String> processTreeSignature(Element root) async {
    final bufferTree = _serializeTree(root);
    return await _hashSignature(bufferTree);
  }

  /// Helper recursive to visit the `element` children to produce a compact
  /// signature `buffer` with [StringBuffer].
  ///
  /// Sign the `buffer` with the [Widget] element `runtimeType` and if exits,
  /// the `key`.
  ///
  /// This helper is important because it allows detecting when elements have not
  /// changed, ensuring that heavy processing is skipped if the widget structure
  /// remains the same.
  ///
  /// Output bash example:
  /// ```bash
  /// "<Padding,visible:true>"
  /// "<Text,visible:true>"
  /// "<Icon,visible:false>"
  /// "<RichText,visible:false>"
  /// ```
  static void _buildElementTreeBuffer(Element element, StringBuffer buffer) {
    final Widget widget = element.widget;

    final isVisible = isWidgetVisible(element);

    buffer.write('<${widget.runtimeType},visible:$isVisible>');

    element.visitChildElements((child) {
      _buildElementTreeBuffer(child, buffer);
    });
  }

  /// Validates if the `element` is visible or not.
  static bool isWidgetVisible(Element element) {
    final renderObject = element.renderObject;

    if (renderObject == null || !renderObject.attached) return false;

    if (renderObject is RenderBox &&
        (!renderObject.hasSize || renderObject.size.isEmpty)) {
      return false;
    }

    bool isHidden = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Offstage &&
          (ancestor.widget as Offstage).offstage) {
        isHidden = true;
        return false;
      }
      if (ancestor.widget is Opacity &&
          (ancestor.widget as Opacity).opacity == 0.0) {
        isHidden = true;
        return false;
      }
      if (ancestor.widget is Visibility &&
          !(ancestor.widget as Visibility).visible) {
        isHidden = true;
        return false;
      }
      return true;
    });

    return !isHidden;
  }

  /// Returns the current value of the provided `key` if exist.
  ///
  /// ```
  /// ValueKey('login_button') => login_button
  /// or
  /// GlobalKey<FormState>#bf22a
  /// ```
  static String keyToString(Key key) {
    final String keyToString = key.toString();

    final RegExpMatch? match = RegExp(r"\'(.+)\'").firstMatch(keyToString);

    if (match != null) return match.group(1)!;
    return keyToString;
  }

  /// Creates a [String] key from the provided `route`.
  ///
  /// To has a unique key ...
  static String createKeyRoute(Route<dynamic> route, BuildContext? context) {
    if (context is! Element || !context.mounted) return "context:unmounted";

    String routeName = "no-route-name";
    String widgetKey = "no-widget-key";
    String stateKey = "no-state-key";

    final ModalRoute<dynamic>? modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      final String? name = modalRoute.settings.name;
      if (name != null && name.isNotEmpty) {
        routeName = name;
      }
    } else {
      final String? name = route.settings.name;
      if (name != null && name.isNotEmpty) {
        routeName = name;
      }
    }

    final String routeType = route.runtimeType.toString();
    final String routeId = (route.navigator?.hashCode ?? 0).toString();

    final Widget widget = context.widget;
    final Key? key = widget.key;
    if (key != null) {
      widgetKey = keyToString(key);
    }

    try {
      final stateType = context.findAncestorStateOfType();
      if (stateType != null) {
        final Key? key = stateType.widget.key;
        if (key != null) stateKey = keyToString(key);

        stateKey = "${stateType.widget.runtimeType}#${stateKey.hashCode}";
      }
    } catch (_) {}

    return '$routeName:$routeType:$routeId:$widgetKey:$stateKey';
  }
}
