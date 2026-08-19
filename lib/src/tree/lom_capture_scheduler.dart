import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

/// Capture causes ordered by conceptual precedence.
///
/// Navigation owns the strongest barrier. Pointer-down priorities can advance
/// pending post-scroll or dirty-state work. Stabilized scroll work precedes
/// ordinary mutation debounce work.
///
/// The declaration order documents conceptual precedence only. Scheduling
/// rules enforce precedence; enum indexes are never compared.
enum LomCaptureReason {
  navigation,
  postScrollPointerDown,
  dirtyPointerDown,
  scrollEnd,
  ordinaryMutation,
}

typedef LomCaptureCallback =
    LomAbstract? Function(bool comesFromNavigation);

/// Owns LOM capture state, priority decisions, and timer scheduling.
class LomCaptureScheduler {
  LomCaptureScheduler({required LomCaptureCallback captureLom})
    : _captureLom = captureLom;

  final LomCaptureCallback _captureLom;

  bool _isRunning = false;
  bool _isNavigationBarrierActive = false;
  bool _isScrollCaptureSuppressed = false;
  bool _hasUncapturedTreeChange = true;
  bool _hasDeferredMutationCapture = false;
  bool _needsPostScrollCapture = false;
  bool _hasAttemptedPriorityCaptureForCurrentState = false;
  int _navigationEpoch = 0;
  Timer? _captureTimer;
  DateTime _lastCaptureTime = DateTime.fromMillisecondsSinceEpoch(0);

  @pragma('vm:prefer-inline')
  bool get isRunning => _isRunning;

  @pragma('vm:prefer-inline')
  bool get hasPendingPostScrollCapture => _needsPostScrollCapture;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
  }

  void dispose() {
    _isRunning = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    _isNavigationBarrierActive = false;
    _isScrollCaptureSuppressed = false;
    _hasDeferredMutationCapture = false;
    _needsPostScrollCapture = false;
    _hasUncapturedTreeChange = false;
    _hasAttemptedPriorityCaptureForCurrentState = false;
    _navigationEpoch += 1;
  }

  @pragma('vm:prefer-inline')
  void setCurrentlyNavigating() {
    _navigationEpoch += 1;
    if (_captureTimer != null) {
      if (_captureTimer!.isActive) _deferMutationCapture();
      _captureTimer?.cancel();
      _captureTimer = null;
    }
    _isNavigationBarrierActive = true;
  }

  void setScrollActive(bool isActive) {
    _isScrollCaptureSuppressed = isActive;
    if (isActive) {
      final interruptedNavigation = _isNavigationBarrierActive;
      _captureTimer?.cancel();
      _captureTimer = null;
      if (interruptedNavigation) {
        _navigationEpoch += 1;
        _isNavigationBarrierActive = false;
        _hasDeferredMutationCapture = false;
      }
    }
  }

  void markPostScrollCapturePending() {
    if (!_isRunning) return;

    _needsPostScrollCapture = true;
    _hasUncapturedTreeChange = true;
    _hasAttemptedPriorityCaptureForCurrentState = false;
  }

  void capturePendingPostScrollLom() {
    if (!_isRunning ||
        !_needsPostScrollCapture ||
        _isNavigationBarrierActive ||
        _isScrollCaptureSuppressed) {
      return;
    }

    _captureNow(
      LomCaptureReason.scrollEnd,
      comesFromNavigation: false,
      bypassCooldown: true,
    );
  }

  void handleBuildScheduled() {
    if (!_isRunning || _isScrollCaptureSuppressed) return;

    _markTreeChanged();
    if (_isNavigationBarrierActive) {
      _deferMutationCapture();
      return;
    }

    _scheduleDebouncedCapture();
  }

  void captureTree(
    bool comesFromNavigation, {
    bool bypassCooldown = false,
  }) {
    if (comesFromNavigation) {
      if (!_isRunning ||
          !_isNavigationBarrierActive ||
          _isScrollCaptureSuppressed) {
        return;
      }
      if (_captureTimer?.isActive ?? false) return;

      final scheduledNavigationEpoch = _navigationEpoch;
      _captureTimer = Timer(kDebounceTime, () {
        _captureTimer = null;
        if (!_isRunning ||
            scheduledNavigationEpoch != _navigationEpoch ||
            !_isNavigationBarrierActive ||
            _isScrollCaptureSuppressed) {
          return;
        }
        _captureNow(
          LomCaptureReason.navigation,
          comesFromNavigation: true,
          navigationEpoch: scheduledNavigationEpoch,
        );
      });
      return;
    }

    _captureNow(
      null,
      comesFromNavigation: false,
      bypassCooldown: bypassCooldown,
    );
  }

  /// A priority capture can improve a first pointer's current LOM state, but a
  /// blocked or failed capture never replaces a non-empty ref with ''.
  ({String lomRef, bool isResolved}) resolveLomStateForPointerDown({
    required String currentLomRef,
  }) {
    if (!_isRunning || _isNavigationBarrierActive) {
      return (lomRef: currentLomRef, isResolved: false);
    }

    if (_needsPostScrollCapture) {
      if (_hasAttemptedPriorityCaptureForCurrentState) {
        return (lomRef: currentLomRef, isResolved: false);
      }

      _hasAttemptedPriorityCaptureForCurrentState = true;

      try {
        final lom = _captureNow(
          LomCaptureReason.postScrollPointerDown,
          comesFromNavigation: false,
          bypassCooldown: true,
        );
        if (lom != null) {
          final lomRef = _preserveCurrentLomRef(lom.id, currentLomRef);
          return (lomRef: lomRef, isResolved: lom.id.isNotEmpty);
        }
      } catch (error, stackTrace) {
        _logPriorityCaptureError(
          LomCaptureReason.postScrollPointerDown,
          error,
          stackTrace,
        );
      }

      return (lomRef: currentLomRef, isResolved: false);
    }

    if (_isScrollCaptureSuppressed || !_hasUncapturedTreeChange) {
      return (
        lomRef: currentLomRef,
        isResolved: currentLomRef.isNotEmpty && !_hasUncapturedTreeChange,
      );
    }
    if (_hasAttemptedPriorityCaptureForCurrentState) {
      return (lomRef: currentLomRef, isResolved: false);
    }

    _hasAttemptedPriorityCaptureForCurrentState = true;

    try {
      final lom = _captureNow(
        LomCaptureReason.dirtyPointerDown,
        comesFromNavigation: false,
        bypassCooldown: true,
      );
      if (lom != null) {
        final lomRef = _preserveCurrentLomRef(lom.id, currentLomRef);
        return (lomRef: lomRef, isResolved: lom.id.isNotEmpty);
      }
    } catch (error, stackTrace) {
      _logPriorityCaptureError(
        LomCaptureReason.dirtyPointerDown,
        error,
        stackTrace,
      );
    }

    _scheduleDebouncedCapture(restart: false);
    return (lomRef: currentLomRef, isResolved: false);
  }

  String _preserveCurrentLomRef(
    String resolvedLomRef,
    String currentLomRef,
  ) {
    if (resolvedLomRef.isEmpty && currentLomRef.isNotEmpty) {
      return currentLomRef;
    }
    return resolvedLomRef;
  }

  LomAbstract? _captureNow(
    LomCaptureReason? reason, {
    required bool comesFromNavigation,
    bool bypassCooldown = false,
    int? navigationEpoch,
  }) {
    if (reason != null) _logCaptureReason(reason);

    if (!comesFromNavigation && _isNavigationBarrierActive) {
      _deferMutationCapture();
      return null;
    }

    if (comesFromNavigation) _isNavigationBarrierActive = true;
    var navigationCaptureProducedLom = false;

    final now = DateTime.now();
    final elapsedSinceLastCapture = now.difference(_lastCaptureTime);
    if (!comesFromNavigation &&
        !bypassCooldown &&
        elapsedSinceLastCapture.inMilliseconds <
            kCooldownTime.inMilliseconds) {
      if (_isRunning &&
          _hasUncapturedTreeChange &&
          !_isNavigationBarrierActive &&
          !_isScrollCaptureSuppressed) {
        _scheduleDebouncedCapture(
          delay: kCooldownTime - elapsedSinceLastCapture,
        );
      }
      return null;
    }

    try {
      final lom = _captureLom(comesFromNavigation);
      if (lom == null) return null;

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

  void _deferMutationCapture() {
    _hasDeferredMutationCapture = true;
  }

  void _markTreeChanged() {
    _hasUncapturedTreeChange = true;
    if (!_needsPostScrollCapture) {
      _hasAttemptedPriorityCaptureForCurrentState = false;
    }
  }

  void _markTreeCaptured() {
    _needsPostScrollCapture = false;
    _hasUncapturedTreeChange = false;
    _hasAttemptedPriorityCaptureForCurrentState = false;
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  void _scheduleDebouncedCapture({
    bool restart = true,
    Duration delay = kDebounceTime,
  }) {
    if (!_isRunning ||
        !_hasUncapturedTreeChange ||
        _isNavigationBarrierActive ||
        _isScrollCaptureSuppressed) {
      return;
    }
    if (!restart && (_captureTimer?.isActive ?? false)) return;

    _captureTimer?.cancel();
    _captureTimer = Timer(delay, () {
      _captureTimer = null;
      if (!_isRunning ||
          !_hasUncapturedTreeChange ||
          _isScrollCaptureSuppressed) {
        return;
      }

      _captureNow(
        LomCaptureReason.ordinaryMutation,
        comesFromNavigation: false,
      );
    });
  }

  void _completeNavigationCapture(
    bool navigationCaptureProducedLom,
    int completedNavigationEpoch,
  ) {
    if (completedNavigationEpoch != _navigationEpoch) return;

    final hadDeferredCapture = _hasDeferredMutationCapture;
    _hasDeferredMutationCapture = false;
    _isNavigationBarrierActive = false;

    if (navigationCaptureProducedLom || !hadDeferredCapture || !_isRunning) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isRunning || completedNavigationEpoch != _navigationEpoch) return;
      _captureNow(
        LomCaptureReason.navigation,
        comesFromNavigation: false,
        bypassCooldown: true,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _logCaptureReason(LomCaptureReason reason) {
    try {
      SessionLogger.verbose('LOM capture attempt reason=${reason.name}');
    } catch (_) {
      // Diagnostics cannot affect capture or the client application.
    }
  }

  void _logPriorityCaptureError(
    LomCaptureReason reason,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      SessionLogger.error(
        'Priority tree capture failed reason=${reason.name}',
        error,
        stackTrace,
      );
    } catch (_) {
      // A client logger cannot break pointer delivery.
    }
  }
}
