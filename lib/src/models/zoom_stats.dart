class ZoomStats {
  /// Average radial movement (in pixels).
  ///
  /// Indicates how far, on average, the fingers move away (>0) or closer (<0)
  /// to the center.
  ///
  /// - __positive__: zoom out,
  /// - __negative__: zoom in.
  final double avgRadial;

  /// Mean square deviation of tangential movement.
  ///
  /// Measures how much the fingers rotate around the center (rotation).
  /// - __Low values__: straight movement (pure zoom);
  /// - __High values__: possible rotation.
  final double tangentialRms;

  /// Percentage of fingers moving in the same radial direction.
  ///
  /// - 1.0 = all consistent (clear zoom)
  /// - 0.5 = half move away and half move closer.
  final double consistency;

  ZoomStats({
    required this.avgRadial,
    required this.tangentialRms,
    required this.consistency,
  });

  factory ZoomStats.zero() => ZoomStats(
        avgRadial: 0,
        tangentialRms: 0,
        consistency: 0,
      );

  @override
  String toString() =>
      'ZoomStats(avgRadial: $avgRadial, tangentialRms: $tangentialRms, consistency: $consistency)';
}
