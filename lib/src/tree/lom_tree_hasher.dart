import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:session_recorder_flutter/src/models/models.dart' show Root;

class LomTreeHasher {
  /// Logical-pixel tolerance to ignore micro-movements.
  static const int _tolerance = 4;

  static int _bucket(double value) => (value / _tolerance).round();

  /// f1 hashes UTF-8 JSON: [rootCount, [x4,y4,w4,h4,childCount,t], ...].
  /// Nodes follow preorder; child counts preserve the ordered tree structure.
  /// IDs, timestamps and viewport dimensions are deliberately excluded.
  static String signatureRoots(List<Root> roots) {
    final input = StringBuffer('[')..write(roots.length);

    void traverse(List<Root> nodes) {
      for (final root in nodes) {
        input
          ..write(',[')
          ..write(_bucket(root.box.left))
          ..write(',')
          ..write(_bucket(root.box.top))
          ..write(',')
          ..write(_bucket(root.box.width))
          ..write(',')
          ..write(_bucket(root.box.height))
          ..write(',')
          ..write(root.children.length)
          ..write(',')
          ..write(jsonEncode(root.widgetType))
          ..write(']');
        traverse(root.children);
      }
    }

    traverse(roots);
    input.write(']');
    final digest = sha256.convert(utf8.encode(input.toString()));
    return 'f1_${digest.toString().substring(0, 24)}';
  }
}
