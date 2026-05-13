import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

/// Watches for widget tree structural changes and captures snapshots.

class TreeDetector {
  final SessionRecorderEngine _engine;
  final LomTreeInspector _inspector;

  TreeDetector({required SessionRecorderEngine engine})
    : _engine = engine,
      _inspector = LomTreeInspector(engine.config);

  bool _isRunning = false;

  @pragma('vm:prefer-inline')
  bool get isRunning => _isRunning;

  @pragma('vm:prefer-inline')
  Element? get currentRouteElement => _engine.context.currentRouteElement;

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
      final element = _getSafeElement();

      if (element == null) {
        SessionLogger.warning(
          "No route could be found to capture. Provide the `SessionNavigatorObserver`",
        );
        return;
      }

      final lom = _inspector.captureLom(element);

      if (lom == null) return;

      _lastCaptureTime = DateTime.now();

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

  Element? _getSafeElement() {
    if (currentRouteElement != null) return currentRouteElement;

    Element? fallbackElement;

    WidgetsBinding.instance.rootElement?.visitChildren((Element rootChild) {
      void findNavigator(Element element) {
        if (element.widget is Navigator) {
          fallbackElement = element;
          return;
        }
        element.visitChildren(findNavigator);
      }

      findNavigator(rootChild);
    });

    if (fallbackElement != null) {
      SessionLogger.warning(
        "The brute-force fallback was used to find the element. Please provide the `SessionNavigatorObserver` instance. For more information go to the GitHub's Repository",
      );
    }

    return fallbackElement;
  }

  // static void _printTree(List<Root> nodes, int indent) {
  //   for (final node in nodes) {
  //     debugPrint('${'  ' * indent}${node.id} - ${node.widgetType}');
  //     _printTree(node.children, indent + 1);
  //   }
  // }
}
