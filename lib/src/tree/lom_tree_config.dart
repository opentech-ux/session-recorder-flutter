import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

/// Controls which widget types appear in the captured tree.
class LomTreeConfig {
  final Map<Type, String> pruneAt;
  final Set<String> ignoreAt;
  final Map<Type, String> noiseAt;
  final Map<Type, String> semantics;

  // Concrete public types covered by the existing ignoreAt substrings.
  static const ignoredTypes = <Type, String>{
    Listener: 'Listener',
    ClipRect: 'ClipRect',
    ClipRRect: 'ClipRRect',
    ClipOval: 'ClipOval',
    ClipPath: 'ClipPath',
    Transform: 'Transform',
    CompositedTransformTarget: 'CompositedTransformTarget',
    FadeTransition: 'FadeTransition',
    Offstage: 'Offstage',
    Viewport: 'Viewport',
    ShrinkWrappingViewport: 'ShrinkWrappingViewport',
    NestedScrollViewViewport: 'NestedScrollViewViewport',
    LayoutBuilder: 'LayoutBuilder',
    SliverLayoutBuilder: 'SliverLayoutBuilder',
    SizeChangedLayoutNotifier: 'SizeChangedLayoutNotifier',
    OverflowBox: 'OverflowBox',
    SizedOverflowBox: 'SizedOverflowBox',
    CustomSingleChildLayout: 'CustomSingleChildLayout',
    CustomMultiChildLayout: 'CustomMultiChildLayout',
    MouseRegion: 'MouseRegion',
    Semantics: 'Semantics',
    MergeSemantics: 'MergeSemantics',
    IndexedSemantics: 'IndexedSemantics',
    SliverOffstage: 'SliverOffstage',
    SliverIgnorePointer: 'SliverIgnorePointer',
    // The former 'Overlay' substring matched this exact type argument.
    AnnotatedRegion<SystemUiOverlayStyle>:
        'AnnotatedRegion<SystemUiOverlayStyle>',
  };

  // Already retained physical widgets; naming does not add filter exceptions.
  static const _retainedNames = <Type, String>{
    DecoratedBox: 'DecoratedBox',
    RawImage: 'RawImage',
    RichText: 'RichText',
  };

  String? canonicalName(Type type) =>
      pruneAt[type] ??
      semantics[type] ??
      noiseAt[type] ??
      ignoredTypes[type] ??
      _retainedNames[type];

  const LomTreeConfig({
    this.pruneAt = const {
      SnapshotWidget: 'SnapshotWidget',
      BlockSemantics: 'BlockSemantics',
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
      'Transform',
      'Viewport',
      'Layout',
      'Overflow',
    },
    this.noiseAt = const {
      Padding: 'Padding',
      Center: 'Center',
      Column: 'Column',
      Stack: 'Stack',
      Row: 'Row',
      SizedBox: 'SizedBox',
      Align: 'Align',
      Expanded: 'Expanded',
      Flexible: 'Flexible',
      Container: 'Container',
      FittedBox: 'FittedBox',
      ConstrainedBox: 'ConstrainedBox',
      LimitedBox: 'LimitedBox',
      ColoredBox: 'ColoredBox',
      RepaintBoundary: 'RepaintBoundary',
      SafeArea: 'SafeArea',
      FractionallySizedBox: 'FractionallySizedBox',
      FractionalTranslation: 'FractionalTranslation',
      IgnorePointer: 'IgnorePointer',
      AbsorbPointer: 'AbsorbPointer',
      TapRegion: 'TapRegion',
      GestureDetector: 'GestureDetector',
      RawGestureDetector: 'RawGestureDetector',
      MetaData: 'MetaData',
      PhysicalModel: 'PhysicalModel',
      AnimatedPhysicalModel: 'AnimatedPhysicalModel',
      PhysicalShape: 'PhysicalShape',
      CustomPaint: 'CustomPaint',
      TextFieldTapRegion: 'TextFieldTapRegion',
      ExcludeSemantics: 'ExcludeSemantics',
      ImageFiltered: 'ImageFiltered',
    },
    this.semantics = const {
      TextField: 'TextField',
      TextFormField: 'TextFormField',
      ElevatedButton: 'ElevatedButton',
      TextButton: 'TextButton',
      OutlinedButton: 'OutlinedButton',
      IconButton: 'IconButton',
      Card: 'Card',
      Switch: 'Switch',
      Checkbox: 'Checkbox',
      InkWell: 'InkWell',
      Image: 'Image',
      Icon: 'Icon',
      NavigationBar: 'NavigationBar',
      BottomNavigationBar: 'BottomNavigationBar',
      NavigationRail: 'NavigationRail',
      PhysicalModel: 'PhysicalModel',
      PhysicalShape: 'PhysicalShape',
    },
  });
}
