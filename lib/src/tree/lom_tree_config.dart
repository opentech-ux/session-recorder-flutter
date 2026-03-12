class LomTreeConfig {
  // TODO : more configuration in the future

  final Set<String> pruneAt;
  final Set<String> ignoreAt;

  const LomTreeConfig({
    this.pruneAt = const {
      'SnapshotWidget',
      'ConstrainedBox',
      'PhysicalShape',
      'LimitedBox',
      'TapRegion',
      'DecoratedBox',
      'RepaintBoundary',
      'CustomPaint',
      'MetaData',
      'ColoredBox',
      'PhysicalModel',
      'AnimatedPhysicalModel',
      'CustomMultiChildLayout',
      'RawGestureDetector',
      'MouseRegion',
      'Semantics',
      'BlockSemantics',
      'ExcludeSemantics',
      'MergeSemantics',
      'IgnorePointer',
      'AbsorbPointer',
    },
    this.ignoreAt = const {
      'Semantics',
      'Listener',
      'Pointer',
      'Controller',
      'Scope',
      'Clip',
      'Focus',
      'Navigator',
      'Overlay',
      'Model',
      'Transition',
      'Offstage',
      'Mouse',
      'TextField',
      'Transform',
      'Image',
      'Viewport',
      'Layout',
      'Overflow',
      'Align',
    },
  });
}
