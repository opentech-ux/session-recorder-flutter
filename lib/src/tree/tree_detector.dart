import 'dart:async';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';

import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

/// Watches for widget tree structural changes and captures snapshots.

class TreeDetector {
  final SessionRecorderEngine _engine;
  final LomTreeConfig _config;

  TreeDetector({
    required SessionRecorderEngine engine,
    LomTreeConfig config = const LomTreeConfig(),
  }) : _engine = engine,
       _config = config;

  bool _isRunning = false;

  @pragma('vm:prefer-inline')
  bool get isRunning => _isRunning;

  bool _isBuilded = false;
  bool _isNavigating = false;
  bool _isNotifierLocked = false;

  /// Timer used to handle debouncing of widget tree captures.
  ///
  ///  - Acts as a delay mechanism **(300ms)** to avoid capturing the widget
  /// tree on every minor change.
  ///  - The timer resets on each detected change and only triggers once no
  /// further updates occur within the debounce window.
  ///  - Helps reduce redundant or heavy operations by batching changes.
  Timer? _debounce;
  VoidCallback? _lastOnBuildScheduled;
  DateTime _lastCaptureTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Holds the latest captured snapshot.
  /// Used by `[TreeOverlay]` to repaint the debug overlay automatically.
  final ValueNotifier<LomAbstract?> notifier = ValueNotifier(null);

  @pragma('vm:prefer-inline')
  void setCurrentlyNavigating() => _isNavigating = true;

  /// Starts watching for tree changes.
  void detect() {
    if (_isRunning) return;
    _isRunning = true;
    _buildOrDefer();
  }

  void _buildOrDefer() {
    final buildOwner = WidgetsBinding.instance.buildOwner;

    if (buildOwner == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isRunning) _buildOrDefer();
      });
      return;
    }

    if (_isBuilded) return;

    _lastOnBuildScheduled = buildOwner.onBuildScheduled;

    buildOwner.onBuildScheduled = () {
      _lastOnBuildScheduled?.call();

      if (!_isRunning || _isNavigating) return;

      if (_isNotifierLocked) return;

      _debounce?.cancel();
      _debounce = Timer(kDebounceTime, () {
        if (!_isRunning || _isNavigating) return;

        captureTree(false);
      });
    };

    _isBuilded = true;
  }

  void captureTree(bool comesFromNavigation) {
    if (comesFromNavigation) _isNavigating = true;

    final now = DateTime.now();
    if (now.difference(_lastCaptureTime).inMilliseconds <
        kCooldownTime.inMilliseconds) {
      if (comesFromNavigation) _isNavigating = false;
      return;
    }

    try {
      final lom = LomTreeInspector.captureLom(
        _engine.recorder.currentRouteElement,
        config: _config,
      );

      if (lom == null) return;

      _lastCaptureTime = DateTime.now();

      _isNotifierLocked = true;
      try {
        notifier.value = lom;
      } finally {
        _isNotifierLocked = false;
      }

      _printTree([lom.root!], 0);
      _engine.recorder.recordLom(lom);
    } finally {
      if (comesFromNavigation) _isNavigating = false;
    }
  }

  static void _printTree(List<Root> nodes, int indent) {
    for (final node in nodes) {
      debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
      _printTree(node.children, indent + 1);
    }
  }
}
