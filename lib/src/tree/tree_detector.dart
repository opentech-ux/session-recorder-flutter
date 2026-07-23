import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';
import 'package:session_recorder_flutter/src/tree/lom_capture_scheduler.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

/// Watches for widget tree structural changes and executes LOM captures.
class TreeDetector {
  static TreeDetector? _activeDetector;

  TreeDetector({required SessionRecorderEngine engine})
    : _engine = engine,
      _inspector = LomTreeInspector() {
    _scheduler = LomCaptureScheduler(captureLom: _captureTreeNow);
  }

  final SessionRecorderEngine _engine;
  final LomTreeInspector _inspector;
  late final LomCaptureScheduler _scheduler;

  Element? _captureElement;
  bool _isBuildHookInstalled = false;
  bool _isPublishingCapture = false;
  VoidCallback? _lastOnBuildScheduled;
  VoidCallback? _installedOnBuildScheduled;

  /// Holds the latest captured snapshot.
  /// Used by `[TreeOverlay]` to repaint the debug overlay automatically.
  final ValueNotifier<LomAbstract?> notifier = ValueNotifier(null);

  @pragma('vm:prefer-inline')
  bool get isRunning => _scheduler.isRunning;

  @pragma('vm:prefer-inline')
  bool get hasPendingPostScrollCapture =>
      _scheduler.hasPendingPostScrollCapture;

  static void registerCaptureElement(Element element) {
    _activeDetector?._captureElement = element;
  }

  static void clearCaptureElement(Element element) {
    final detector = _activeDetector;
    if (detector != null && identical(detector._captureElement, element)) {
      detector._captureElement = null;
    }
  }

  @pragma('vm:prefer-inline')
  void setCurrentlyNavigating() {
    _scheduler.setCurrentlyNavigating();
  }

  void setScrollActive(bool isActive) {
    _scheduler.setScrollActive(isActive);
  }

  void markPostScrollCapturePending() {
    _scheduler.markPostScrollCapturePending();
  }

  void capturePendingPostScrollLom() {
    _scheduler.capturePendingPostScrollLom();
  }

  /// Starts watching for tree changes.
  void detect() {
    if (_scheduler.isRunning) return;
    _scheduler.start();
    _activeDetector = this;
    _buildOrDefer();
  }

  void _buildOrDefer() {
    final buildOwner = WidgetsBinding.instance.buildOwner;

    if (buildOwner == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scheduler.isRunning) _buildOrDefer();
      });
      return;
    }

    if (_isBuildHookInstalled) return;

    _lastOnBuildScheduled = buildOwner.onBuildScheduled;

    void onBuildScheduled() {
      _lastOnBuildScheduled?.call();

      if (_isPublishingCapture) return;
      _scheduler.handleBuildScheduled();
    }

    _installedOnBuildScheduled = onBuildScheduled;
    buildOwner.onBuildScheduled = onBuildScheduled;
    _isBuildHookInstalled = true;
  }

  /// Stops tree detection and restores the previous build hook.
  void dispose() {
    _scheduler.dispose();

    final buildOwner = WidgetsBinding.instance.buildOwner;
    final installedCallback = _installedOnBuildScheduled;

    final didRestoreHook =
        _isBuildHookInstalled &&
        buildOwner != null &&
        installedCallback != null &&
        identical(buildOwner.onBuildScheduled, installedCallback);

    if (didRestoreHook) {
      buildOwner.onBuildScheduled = _lastOnBuildScheduled;
    }

    _isBuildHookInstalled = false;
    _isPublishingCapture = false;
    _captureElement = null;
    if (identical(_activeDetector, this)) _activeDetector = null;

    // Keep forwarding intact if another callback wrapped ours after install.
    if (didRestoreHook || buildOwner == null) {
      _lastOnBuildScheduled = null;
      _installedOnBuildScheduled = null;
    }

    notifier.dispose();
  }

  void captureTree(bool comesFromNavigation, {bool bypassCooldown = false}) {
    _scheduler.captureTree(
      comesFromNavigation,
      bypassCooldown: bypassCooldown,
    );
  }

  /// Resolves the LOM reference to freeze into a new pointer trace.
  String resolveLomRefForPointerDown({String? inheritedLomRef}) {
    final currentLomRef = _engine.context.currentLomRef ?? '';

    return _scheduler.resolveLomRefForPointerDown(
      inheritedLomRef: inheritedLomRef,
      currentLomRef: currentLomRef,
    );
  }

  LomAbstract? _captureTreeNow(bool comesFromNavigation) {
    final element = _captureElement;

    if (element == null || !element.mounted) {
      if (element != null && identical(_captureElement, element)) {
        _captureElement = null;
      }
      SessionLogger.warning(
        "The capture subtree is not available or is no longer mounted",
      );
      return null;
    }

    final lom = _inspector.captureLom(
      element,
      comesFromNavigation: comesFromNavigation,
    );

    if (lom == null) return null;

    _isPublishingCapture = true;
    try {
      notifier.value = lom;
    } finally {
      _isPublishingCapture = false;
    }

    // _printTree([lom.root!], 0);

    _engine.context.recordLom(lom);
    return lom;
  }

  // static void _printTree(List<Root> nodes, int indent) {
  //   for (final node in nodes) {
  //     debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
  //     _printTree(node.children, indent + 1);
  //   }
  // }
}
