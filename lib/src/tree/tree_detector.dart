import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_config.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

class TreeDetector {
  final SessionRecorderInternal recorder;
  final LomTreeConfig config;

  TreeDetector({required this.recorder, this.config = const LomTreeConfig()});

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isPendingCapture = false;
  bool _isPostFrameQueued = false;
  bool _isBuilded = false;
  bool _isPendingNavigation = false;

  String _lastSignature = '';
  DateTime _lastCaptureTime = DateTime.fromMillisecondsSinceEpoch(0);

  VoidCallback? _lastOnBuildScheduled;

  ///
  void detect() {
    if (_isRunning) return;

    _isRunning = true;
    _buildOrDefer();
  }

  ///
  void _buildOrDefer() {
    final buildOwner = WidgetsBinding.instance.buildOwner;

    if (buildOwner == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isRunning) _buildOrDefer();
      });
      return;
    }

    /// Already builded the [BuildOwner] (e.g detect() called twice across a hot
    /// restart).
    if (_isBuilded) return;

    _lastOnBuildScheduled = buildOwner.onBuildScheduled;

    buildOwner.onBuildScheduled = () {
      _lastOnBuildScheduled?.call();

      if (!_isRunning) return;

      _isPendingCapture = true;

      if (!_isPostFrameQueued) {
        _isPostFrameQueued = true;
        WidgetsBinding.instance.addPostFrameCallback(_onRequestCapture);
      }
    };

    _isBuilded = true;
  }

  ///
  void _onRequestCapture(Duration _) {
    _isPostFrameQueued = false;

    debugPrint(">> _onRequestCapture");

    if (!_isRunning || !_isPendingCapture) return;

    _isPendingCapture = false;

    debugPrint(">> _onRequestCapture 2");

    debugPrint(">> _isPendingNavigation : $_isPendingNavigation");

    if (_isPendingNavigation) return;

    final DateTime now = DateTime.now();

    /// Minimum [200] ms between consecutive captures
    if (now.difference(_lastCaptureTime).inMilliseconds < 500) {
      debugPrint(">> multiple 3");

      return;
    }

    debugPrint(">> REQUEST CAPTURE");

    /// Capture queued
    captureTree(false);
  }

  ///
  void currentlyNavigation() => _isPendingNavigation = true;

  ///
  void captureTree(bool comesFromNavigation) {
    if (comesFromNavigation) _isPendingNavigation = true;

    Future.microtask(() {
      if (!comesFromNavigation) if (_isPendingCapture) return;

      try {
        final lom = LomTreeInspector.captureLom(
          recorder.currentRouteElement,
          config: config,
        );

        if (lom == null) return;

        /// If the stable structure did not change, no additional processing is
        /// performed.
        if (lom.signature == _lastSignature) return;

        _lastSignature = lom.signature;

        recorder.recordLom(lom);

        _lastCaptureTime = DateTime.now();
      } finally {
        if (comesFromNavigation) _isPendingNavigation = false;
      }
    });
  }
}
