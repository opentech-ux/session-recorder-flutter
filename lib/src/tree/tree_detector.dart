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
  bool _hasPendingOrdinaryCapture = false;
  bool _treeDirty = true;
  bool _priorityCaptureAttemptedForDirtyState = false;
  int _navigationEpoch = 0;

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
  void setCurrentlyNavigating() {
    _navigationEpoch += 1;
    if (_debounce != null) {
      if (_debounce!.isActive) _queuePendingOrdinaryCapture();
      _debounce?.cancel();
      _debounce = null;
    }
    _isNavigating = true;
  }

  void setScrollActive(bool isActive) {
    _isScrollActive = isActive;
    if (isActive) {
      final interruptedNavigation = _isNavigating;
      _debounce?.cancel();
      _debounce = null;
      if (interruptedNavigation) {
        _navigationEpoch += 1;
        _isNavigating = false;
        _hasPendingOrdinaryCapture = false;
      }
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

      if (!_isRunning || _isScrollActive || _isNotifierLocked) return;
      _markTreeDirty();
      if (_isNavigating) {
        _queuePendingOrdinaryCapture();
        return;
      }

      _scheduleDebouncedCapture();
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

    final didRestoreHook =
        _isBuilded &&
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
    _hasPendingOrdinaryCapture = false;
    _treeDirty = false;
    _priorityCaptureAttemptedForDirtyState = false;
    _navigationEpoch += 1;
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
    if (comesFromNavigation) {
      if (!_isRunning || !_isNavigating || _isScrollActive) return;
      if (_debounce?.isActive ?? false) return;

      final scheduledNavigationEpoch = _navigationEpoch;
      _debounce = Timer(kDebounceTime, () {
        _debounce = null;
        if (!_isRunning ||
            scheduledNavigationEpoch != _navigationEpoch ||
            !_isNavigating ||
            _isScrollActive) {
          return;
        }
        _logCaptureReason('navigation');
        _captureTreeNow(
          true,
          navigationEpoch: scheduledNavigationEpoch,
        );
      });
      return;
    }

    _captureTreeNow(false, bypassCooldown: bypassCooldown);
  }

  /// Resolves the LOM reference to freeze into a new pointer trace.
  String resolveLomRefForPointerDown({String? inheritedLomRef}) {
    if (!_isRunning || _isNavigating) return '';
    if (inheritedLomRef != null) return inheritedLomRef;

    final currentLomRef = _engine.context.currentLomRef ?? '';
    if (_isScrollActive || !_treeDirty) return currentLomRef;
    if (_priorityCaptureAttemptedForDirtyState) return '';

    _priorityCaptureAttemptedForDirtyState = true;

    try {
      _logCaptureReason('priority');
      final lom = _captureTreeNow(false, bypassCooldown: true);
      if (lom != null) return lom.id;
    } catch (error, stackTrace) {
      try {
        SessionLogger.error(
          'Priority tree capture failed',
          error,
          stackTrace,
        );
      } catch (_) {
        // A client logger cannot break pointer delivery.
      }
    }

    _scheduleDebouncedCapture(restart: false);
    return '';
  }

  LomAbstract? _captureTreeNow(
    bool comesFromNavigation, {
    bool bypassCooldown = false,
    int? navigationEpoch,
  }) {
    if (!comesFromNavigation && _isNavigating) {
      _queuePendingOrdinaryCapture();
      return null;
    }

    if (comesFromNavigation) _isNavigating = true;
    var navigationCaptureProducedLom = false;

    final now = DateTime.now();
    final elapsedSinceLastCapture = now.difference(_lastCaptureTime);
    if (!comesFromNavigation &&
        !bypassCooldown &&
        elapsedSinceLastCapture.inMilliseconds <
            kCooldownTime.inMilliseconds) {
      if (_isRunning &&
          _treeDirty &&
          !_isNavigating &&
          !_isScrollActive) {
        _scheduleDebouncedCapture(
          delay: kCooldownTime - elapsedSinceLastCapture,
        );
      }
      return null;
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
        return null;
      }

      final lom = _inspector.captureLom(
        element,
        comesFromNavigation: comesFromNavigation,
      );

      if (lom == null) return null;

      _isNotifierLocked = true;
      try {
        notifier.value = lom;
      } finally {
        _isNotifierLocked = false;
      }

      // _printTree([lom.root!], 0);

      _engine.context.recordLom(lom);
      _lastCaptureTime = DateTime.now();
      _markTreeCaptured();
      navigationCaptureProducedLom = comesFromNavigation;
      return lom;
    } finally {
      if (comesFromNavigation) {
        _completeNavigationCapture(
          navigationCaptureProducedLom,
          navigationEpoch!,
        );
      }
    }
  }

  void _queuePendingOrdinaryCapture() {
    _hasPendingOrdinaryCapture = true;
  }

  void _markTreeDirty() {
    _treeDirty = true;
    _priorityCaptureAttemptedForDirtyState = false;
  }

  void _markTreeCaptured() {
    _treeDirty = false;
    _priorityCaptureAttemptedForDirtyState = false;
    _debounce?.cancel();
    _debounce = null;
  }

  void _scheduleDebouncedCapture({
    bool restart = true,
    Duration delay = kDebounceTime,
  }) {
    if (!_isRunning || !_treeDirty || _isNavigating || _isScrollActive) {
      return;
    }
    if (!restart && (_debounce?.isActive ?? false)) return;

    _debounce?.cancel();
    _debounce = Timer(delay, () {
      _debounce = null;
      if (!_isRunning || !_treeDirty || _isScrollActive) return;

      _logCaptureReason('ordinary');
      captureTree(false);
    });
  }

  void _logCaptureReason(String reason) {
    try {
      SessionLogger.verbose('LOM capture attempt reason=$reason');
    } catch (_) {
      // Diagnostics cannot affect capture or the client application.
    }
  }

  void _completeNavigationCapture(
    bool navigationCaptureProducedLom,
    int completedNavigationEpoch,
  ) {
    if (completedNavigationEpoch != _navigationEpoch) return;

    final hadPendingCapture = _hasPendingOrdinaryCapture;
    _hasPendingOrdinaryCapture = false;
    _isNavigating = false;

    if (navigationCaptureProducedLom || !hadPendingCapture || !_isRunning) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRunning || completedNavigationEpoch != _navigationEpoch) return;
      _logCaptureReason('navigation');
      captureTree(false, bypassCooldown: true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // static void _printTree(List<Root> nodes, int indent) {
  //   for (final node in nodes) {
  //     debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
  //     _printTree(node.children, indent + 1);
  //   }
  // }
}
