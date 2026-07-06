import 'package:session_recorder_flutter/src/models/models.dart' show Root;

class LomTreeHasher {
  /// Pixel tolerance to ignore micro-movements
  static const int _tolerance = 4;

  /// Groups pixel values into larger buckets to tolerate small visual changes
  ///
  /// If a buttons moves from X1 (10.1) to X2 (11.8), the `_bucket()` is 3, so
  /// the final hash is exactly the same
  static int _bucket(double value) => (value / _tolerance).round();

  /// Merges a new hash `value` into the global `seed`, ensuring the order of
  /// elements matters
  static int _hashCombine(int seed, int value) =>
      seed ^ (value + 0x9e3779b9 + (seed << 6) + (seed >> 2));

  /// Generates a hash for a single `node` based on its type, position, and
  /// size
  ///
  /// Example :
  /// ```bash
  ///   "Scaffold0,0,97,211|AppBar0,10,97,14|..."
  /// ```
  static int _hashRoot(Root root) {
    int s = 0;

    s = _hashCombine(s, root.widgetType.hashCode);
    s = _hashCombine(s, _bucket(root.box.topLeft.dx));
    s = _hashCombine(s, _bucket(root.box.topLeft.dy));
    s = _hashCombine(s, _bucket(root.box.width));
    s = _hashCombine(s, _bucket(root.box.height));

    return s;
  }

  /// Calculates the global signature of the entire UI tree and returns it
  /// as a hex string.
  ///
  /// Example :
  /// ```bash
  ///   "9264b2f1"
  /// ```
  static String signatureRoots(List<Root> roots) {
    int seed = roots.length;

    void traverse(List<Root> currentRoots) {
      for (Root root in currentRoots) {
        int hash = _hashRoot(root);

        seed = _hashCombine(seed, hash);

        if (root.children.isNotEmpty) {
          traverse(root.children);
        }
      }
    }

    traverse(roots);

    return seed.toRadixString(16);
  }
}
