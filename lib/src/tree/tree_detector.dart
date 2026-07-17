import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

/// Watches for widget tree structural changes and captures snapshots.

class TreeDetector {
  static TreeDetector? _activeDetector;

  final SessionRecorderEngine _engine;
  final LomTreeInspector _inspector;

  TreeDetector({required SessionRecorderEngine engine})
    : _engine = engine,
      _inspector = LomTreeInspector();

  bool _isRunning = false;
  Element? _captureElement;

  @pragma('vm:prefer-inline')
  bool get isRunning => _isRunning;

  static void registerCaptureElement(Element element) {
    _activeDetector?._captureElement = element;
  }

  static void clearCaptureElement(Element element) {
    final detector = _activeDetector;
    if (detector != null && identical(detector._captureElement, element)) {
      detector._captureElement = null;
    }
  }

  bool _isBuilded = false;
  bool _isNavigating = false;
  bool _isScrollActive = false;
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
  VoidCallback? _installedOnBuildScheduled;
  DateTime _lastCaptureTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Holds the latest captured snapshot.
  /// Used by `[TreeOverlay]` to repaint the debug overlay automatically.
  final ValueNotifier<LomAbstract?> notifier = ValueNotifier(null);

  @pragma('vm:prefer-inline')
  void setCurrentlyNavigating() => _isNavigating = true;

  void setScrollActive(bool isActive) {
    _isScrollActive = isActive;
    if (isActive) {
      _debounce?.cancel();
      _debounce = null;
    }
  }

  /// Starts watching for tree changes.
  void detect() {
    if (_isRunning) return;
    _isRunning = true;
    _activeDetector = this;
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

    void onBuildScheduled() {
      _lastOnBuildScheduled?.call();

      if (!_isRunning || _isNavigating || _isScrollActive) return;

      if (_isNotifierLocked) return;

      _debounce?.cancel();
      _debounce = Timer(kDebounceTime, () {
        if (!_isRunning || _isNavigating || _isScrollActive) return;

        captureTree(false);
      });
    }

    _installedOnBuildScheduled = onBuildScheduled;
    buildOwner.onBuildScheduled = onBuildScheduled;
    _isBuilded = true;
  }

  /// Stops tree detection and restores the previous build hook.
  void dispose() {
    _isRunning = false;
    _debounce?.cancel();
    _debounce = null;

    final buildOwner = WidgetsBinding.instance.buildOwner;
    final installedCallback = _installedOnBuildScheduled;

    final didRestoreHook = _isBuilded &&
        buildOwner != null &&
        installedCallback != null &&
        identical(buildOwner.onBuildScheduled, installedCallback);

    if (didRestoreHook) {
      buildOwner.onBuildScheduled = _lastOnBuildScheduled;
    }

    _isBuilded = false;
    _isNavigating = false;
    _isScrollActive = false;
    _isNotifierLocked = false;
    _captureElement = null;
    if (identical(_activeDetector, this)) _activeDetector = null;

    // Keep forwarding intact if another callback wrapped ours after install.
    if (didRestoreHook || buildOwner == null) {
      _lastOnBuildScheduled = null;
      _installedOnBuildScheduled = null;
    }

    notifier.dispose();
  }

  void captureTree(
    bool comesFromNavigation, {
    bool bypassCooldown = false,
  }) {
    if (comesFromNavigation) _isNavigating = true;

    final now = DateTime.now();
    if (!comesFromNavigation &&
        !bypassCooldown &&
        now.difference(_lastCaptureTime).inMilliseconds <
        kCooldownTime.inMilliseconds) {
      return;
    }

    try {
      final element = _captureElement;

      if (element == null || !element.mounted) {
        if (element != null && identical(_captureElement, element)) {
          _captureElement = null;
        }
        SessionLogger.warning(
          "The capture subtree is not available or is no longer mounted",
        );
        return;
      }

      final lom = _inspector.captureLom(
        element,
        comesFromNavigation: comesFromNavigation,
      );

      _lastCaptureTime = DateTime.now();

      if (lom == null) return;

      _isNotifierLocked = true;
      try {
        notifier.value = lom;
      } finally {
        _isNotifierLocked = false;
      }

      // _printTree([lom.root!], 0);

      _engine.context.recordLom(lom);
    } finally {
      if (comesFromNavigation) _isNavigating = false;
    }
  }

  // static void _printTree(List<Root> nodes, int indent) {
  //   for (final node in nodes) {
  //     debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
  //     _printTree(node.children, indent + 1);
  //   }
  // }
}
