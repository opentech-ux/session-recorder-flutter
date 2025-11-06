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
  static Future<String> _hashSignature(String bufferTree) => compute(
        _computeBufferHash,
        bufferTree.toString(),
      );

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
  /// "<Padding>"
  /// "<Text>"
  /// "<Icon>"
  /// "<RichText>"
  /// ```
  /// TODO : Not really sure if the correct way
  static void _buildElementTreeBuffer(
    Element element,
    StringBuffer buffer,
  ) {
    final Widget widget = element.widget;

    buffer.write('<${widget.runtimeType}>');

    element.visitChildElements((child) {
      _buildElementTreeBuffer(child, buffer);
    });
  }
}
