import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

/// Watches for widget tree structural changes and captures snapshots.

class TreeDetector {
  final SessionRecorderInternal recorder;
  final LomTreeConfig config;

  TreeDetector({required this.recorder, this.config = const LomTreeConfig()});

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isPendingCapture = false;
  bool _isPostFrameQueued = false;
  bool _isBuilded = false;
  bool _isNavigating = false;

  DateTime _lastTimeCaptured = DateTime.fromMillisecondsSinceEpoch(0);
  VoidCallback? _lastOnBuildScheduled;

  /// Holds the latest captured snapshot.
  /// Used by `[TreeOverlay]` to repaint the debug overlay automatically.
  final ValueNotifier<LomAbstract?> notifier = ValueNotifier(null);

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

      if (!_isRunning) return;

      // Multiple dirty elements in the same frame set this flag once and
      // register a single postFrameCallback.
      _isPendingCapture = true;

      if (!_isPostFrameQueued) {
        _isPostFrameQueued = true;
        WidgetsBinding.instance.addPostFrameCallback(_onRequestCapture);
      }
    };

    _isBuilded = true;
  }

  void _onRequestCapture(Duration _) {
    _isPostFrameQueued = false;

    debugPrint(">> _onRequestCapture");

    if (!_isRunning || !_isPendingCapture) return;

    _isPendingCapture = false;

    debugPrint(">> _onRequestCapture 2");

    debugPrint(">> _isNavigating : $_isNavigating");

    // Navigation has priority, suppress auto-captures during animations.
    if (_isNavigating) return;

    final DateTime now = DateTime.now();

    // Minimum 500 ms between consecutive captures
    if (now.difference(_lastTimeCaptured).inMilliseconds < 500) {
      debugPrint(">> multiple 3");

      return;
    }

    debugPrint(">> REQUEST CAPTURE");

    /// Capture queued
    captureTree(false);
  }

  void setCurrentlyNavigating() => _isNavigating = true;

  void captureTree(bool comesFromNavigation) {
    if (comesFromNavigation) _isNavigating = true;

    debugPrint("comesFromNavigation : $comesFromNavigation");

    Future.microtask(() {
      debugPrint("_isPendingCapture : $_isPendingCapture");

      if (!comesFromNavigation) if (_isPendingCapture) return;

      try {
        final lom = LomTreeInspector.captureLom(
          recorder.currentRouteElement,
          config: config,
        );

        if (lom == null) return;

        _lastTimeCaptured = DateTime.now();

        _printTree([lom.root!], 0);
        notifier.value = lom;
        recorder.recordLom(lom);

        _lastTimeCaptured = DateTime.now();
      } finally {
        if (comesFromNavigation) _isNavigating = false;
      }
    });
  }

  static void _printTree(List<Root> nodes, int indent) {
    for (final node in nodes) {
      debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
      _printTree(node.children, indent + 1);
    }
  }
}
