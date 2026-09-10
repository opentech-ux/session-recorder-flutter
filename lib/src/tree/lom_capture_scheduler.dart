import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

/// Capture causes ordered by conceptual precedence.
///
/// Navigation owns the strongest barrier. Pointer-down priorities can advance
/// pending post-scroll or dirty-state work. Stabilized scroll work precedes a
/// fixed interaction consequence, which precedes ordinary mutation debounce.
///
/// The declaration order documents conceptual precedence only. Scheduling
/// rules enforce precedence; enum indexes are never compared.
enum LomCaptureReason {
  navigation,
  postScrollPointerDown,
  dirtyPointerDown,
  scrollEnd,
  interactionConsequence,
  ordinaryMutation,
}

typedef LomCaptureCallback = LomAbstract? Function(bool comesFromNavigation);

/// Owns LOM capture state, priority decisions, and timer scheduling.
class LomCaptureScheduler {
  LomCaptureScheduler({required LomCaptureCallback captureLom})
    : _captureLom = captureLom;

  final LomCaptureCallback _captureLom;

  bool _isRunning = false;
  bool _isNavigationBarrierActive = false;
  bool _isScrollCaptureSuppressed = false;

  /// Dirty state means the rendered tree is not represented by a successful
  /// capture; post-scroll debt stays separate for PointerDown priority.
  bool _hasUncapturedTreeChange = true;
  bool _hasDeferredMutationCapture = false;
  bool _needsPostScrollCapture = false;
  bool _hasAttemptedPriorityCaptureForCurrentState = false;

  /// Armed waits for a causal build; scheduled means the fixed deadline owns
  /// the timer and later animation builds must not restart it.
  DateTime? _interactionConsequenceArmedAt;
  bool _isInteractionConsequenceScheduled = false;
  int _navigationEpoch = 0;
  int _mutationRevision = 0;

  /// All LOM deadlines share this timer; their reason determines whether the
  /// deadline is fixed or trailing/restartable.
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
    _interactionConsequenceArmedAt = null;
    _isInteractionConsequenceScheduled = false;
    _navigationEpoch += 1;
  }

  @pragma('vm:prefer-inline')
  void setCurrentlyNavigating() {
    _navigationEpoch += 1;

    /// Navigation cancels weaker deadlines but preserves dirty work so a
    /// failed navigation capture can retry it after the barrier.
    if (_captureTimer != null) {
      if (_captureTimer!.isActive) _deferMutationCapture();
      _captureTimer?.cancel();
      _captureTimer = null;
    }
    _isNavigationBarrierActive = true;
    _interactionConsequenceArmedAt = null;
    _isInteractionConsequenceScheduled = false;
  }

  void setScrollActive(bool isActive) {
    _isScrollCaptureSuppressed = isActive;
    if (isActive) {
      /// Build-driven capture stays suppressed during movement; a fixed
      /// consequence may resume only if no validated scroll supersedes it.
      final interruptedNavigation = _isNavigationBarrierActive;
      _captureTimer?.cancel();
      _captureTimer = null;
      if (interruptedNavigation) {
        _navigationEpoch += 1;
        _isNavigationBarrierActive = false;
        _hasDeferredMutationCapture = false;
      }
    } else if (!_needsPostScrollCapture) {
      // An unvalidated scroll cannot discard pre-existing dirty work. Resume
      // its consequence or ordinary deadline without replacing an active one.
      _scheduleDebouncedCapture(
        restart: false,
        reason: _isInteractionConsequenceScheduled
            ? LomCaptureReason.interactionConsequence
            : LomCaptureReason.ordinaryMutation,
      );
    }
  }

  void armInteractionConsequence() {
    if (!_isRunning || _isNavigationBarrierActive) return;

    /// Consecutive actions share one opportunity; only a lazily expired armed
    /// group may be replaced with a new causal timestamp.
    final armedAt = _interactionConsequenceArmedAt;
    if (armedAt != null &&
        (_isInteractionConsequenceScheduled ||
            DateTime.now().difference(armedAt) <= kDebounceTime)) {
      return;
    }

    _interactionConsequenceArmedAt = DateTime.now();
    _isInteractionConsequenceScheduled = false;
  }

  void markPostScrollCapturePending() {
    if (!_isRunning) return;

    /// Validated scroll debt supersedes a consequence because the stabilized
    /// post-scroll capture is authoritative for the final viewport.
    _needsPostScrollCapture = true;
    _hasUncapturedTreeChange = true;
    _hasAttemptedPriorityCaptureForCurrentState = false;
    if (_isInteractionConsequenceScheduled) {
      _captureTimer?.cancel();
      _captureTimer = null;
    }
    _interactionConsequenceArmedAt = null;
    _isInteractionConsequenceScheduled = false;
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

    _mutationRevision += 1;
    _markTreeChanged();
    if (_isNavigationBarrierActive) {
      _deferMutationCapture();
      return;
    }

    /// A fixed consequence already owns the timer, unlike ordinary trailing
    /// debounce which restarts on every accepted build.
    if (_isInteractionConsequenceScheduled) return;

    final armedAt = _interactionConsequenceArmedAt;
    if (armedAt != null) {
      if (DateTime.now().difference(armedAt) <= kDebounceTime) {
        _isInteractionConsequenceScheduled = true;
        _scheduleDebouncedCapture(
          reason: LomCaptureReason.interactionConsequence,
        );
        return;
      }
      _interactionConsequenceArmedAt = null;
    }

    _scheduleDebouncedCapture();
  }

  void captureTree(bool comesFromNavigation, {bool bypassCooldown = false}) {
    if (comesFromNavigation) {
      if (!_isRunning ||
          !_isNavigationBarrierActive ||
          _isScrollCaptureSuppressed) {
        return;
      }
      if (_captureTimer?.isActive ?? false) return;

      final scheduledNavigationEpoch = _navigationEpoch;

      /// Navigation stabilization is fixed so transition builds cannot defer
      /// its authoritative capture indefinitely.
      _captureTimer = Timer(kDebounceTime, () {
        _captureTimer = null;
        if (!_isRunning ||
            scheduledNavigationEpoch != _navigationEpoch ||
            !_isNavigationBarrierActive ||
            _isScrollCaptureSuppressed) {
          return;
        }

        /// Capture only after the pending frame has committed. [endOfFrame]
        /// schedules a frame when called while idle, so this fence cannot be
        /// skipped merely because no frame was already requested.
        final capturedMutationRevision = _mutationRevision;
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (!_isRunning ||
              scheduledNavigationEpoch != _navigationEpoch ||
              !_isNavigationBarrierActive ||
              _isScrollCaptureSuppressed) {
            return;
          }
          if (_mutationRevision != capturedMutationRevision) {
            // A newer build invalidates this attempt before inspection and
            // publication; hand off dirty work without the null-result retry.
            _completeNavigationCapture(
              false,
              false,
              scheduledNavigationEpoch,
              invalidatedByMutation: true,
            );
            return;
          }
          _captureNow(
            LomCaptureReason.navigation,
            comesFromNavigation: true,
            navigationEpoch: scheduledNavigationEpoch,
            capturedMutationRevision: capturedMutationRevision,
          );
        });
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
    if (!_isRunning) {
      return (lomRef: currentLomRef, isResolved: false);
    }

    if (_isNavigationBarrierActive) {
      if (_hasUncapturedTreeChange) {
        // This publishes the interaction frame, not completion of any debt.
        // In particular, do not enter _captureNow or consume a priority here.
        try {
          final lom = _captureLom(false);
          if (lom != null && lom.ref.isNotEmpty) {
            return (lomRef: lom.ref, isResolved: true);
          }
        } catch (_) {
          // An interaction snapshot failure preserves the unresolved fallback.
        }
      }
      return (lomRef: currentLomRef, isResolved: false);
    }

    /// Post-scroll debt outranks ordinary dirty state because this Down may be
    /// the interaction that stops an otherwise still-suppressed scroll.
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
          final lomRef = _preserveCurrentLomRef(lom.ref, currentLomRef);
          return (lomRef: lomRef, isResolved: lom.ref.isNotEmpty);
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

    /// Only the first Down may advance a dirty capture; later attempts reuse
    /// the frozen fallback until another build creates a new dirty state.
    _hasAttemptedPriorityCaptureForCurrentState = true;

    try {
      final lom = _captureNow(
        LomCaptureReason.dirtyPointerDown,
        comesFromNavigation: false,
        bypassCooldown: true,
      );
      if (lom != null) {
        final lomRef = _preserveCurrentLomRef(lom.ref, currentLomRef);
        return (lomRef: lomRef, isResolved: lom.ref.isNotEmpty);
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

  String _preserveCurrentLomRef(String resolvedLomRef, String currentLomRef) {
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
    int? capturedMutationRevision,
  }) {
    if (!comesFromNavigation && _isNavigationBarrierActive) {
      _deferMutationCapture();
      return null;
    }

    if (comesFromNavigation) _isNavigationBarrierActive = true;
    var navigationCaptureProducedLom = false;

    final now = DateTime.now();
    final elapsedSinceLastCapture = now.difference(_lastCaptureTime);

    /// Cooldown caps inspection frequency without satisfying or discarding the
    /// dirty state that still needs a later capture.
    if (!comesFromNavigation &&
        !bypassCooldown &&
        elapsedSinceLastCapture.inMilliseconds < kCooldownTime.inMilliseconds) {
      /// Cooldown delays a fixed consequence with the same reason so later
      /// builds cannot turn the remaining delay into trailing debounce.
      if (_isRunning &&
          _hasUncapturedTreeChange &&
          !_isNavigationBarrierActive &&
          !_isScrollCaptureSuppressed) {
        _scheduleDebouncedCapture(
          delay: kCooldownTime - elapsedSinceLastCapture,
          reason: reason == LomCaptureReason.interactionConsequence
              ? LomCaptureReason.interactionConsequence
              : LomCaptureReason.ordinaryMutation,
        );
      }
      return null;
    }

    if (reason == LomCaptureReason.interactionConsequence) {
      /// The inspection itself consumes the one fixed opportunity; failure
      /// leaves dirty state for a later ordinary mutation.
      _interactionConsequenceArmedAt = null;
      _isInteractionConsequenceScheduled = false;
    }

    final captureRevision = capturedMutationRevision ?? _mutationRevision;
    var navigationCaptureCoveredLatestMutation = false;

    try {
      final lom = _captureLom(comesFromNavigation);
      if (lom == null) return null;

      _lastCaptureTime = DateTime.now();
      navigationCaptureCoveredLatestMutation = _markTreeCaptured(
        captureRevision,
      );
      navigationCaptureProducedLom = comesFromNavigation;
      return lom;
    } finally {
      if (comesFromNavigation) {
        _completeNavigationCapture(
          navigationCaptureProducedLom,
          navigationCaptureCoveredLatestMutation,
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

  bool _markTreeCaptured(int capturedMutationRevision) {
    /// A valid capture always satisfies existing post-scroll debt, but it must
    /// not erase mutation work observed after the represented revision.
    _needsPostScrollCapture = false;
    if (_mutationRevision != capturedMutationRevision) {
      _hasUncapturedTreeChange = true;
      _hasAttemptedPriorityCaptureForCurrentState = false;
      return false;
    }

    _hasUncapturedTreeChange = false;
    _hasAttemptedPriorityCaptureForCurrentState = false;
    _interactionConsequenceArmedAt = null;
    _isInteractionConsequenceScheduled = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    return true;
  }

  void _scheduleDebouncedCapture({
    bool restart = true,
    Duration delay = kDebounceTime,
    LomCaptureReason reason = LomCaptureReason.ordinaryMutation,
  }) {
    if (!_isRunning ||
        !_hasUncapturedTreeChange ||
        _isNavigationBarrierActive ||
        _isScrollCaptureSuppressed) {
      return;
    }
    if (!restart && (_captureTimer?.isActive ?? false)) return;

    /// Restart is ordinary trailing debounce; fixed callers prevent re-entry
    /// before reaching this shared timer replacement.
    _captureTimer?.cancel();
    _captureTimer = Timer(delay, () {
      _captureTimer = null;
      if (!_isRunning ||
          !_hasUncapturedTreeChange ||
          _isScrollCaptureSuppressed) {
        return;
      }

      _captureNow(reason, comesFromNavigation: false);
    });
  }

  void _completeNavigationCapture(
    bool navigationCaptureProducedLom,
    bool navigationCaptureCoveredLatestMutation,
    int completedNavigationEpoch, {
    bool invalidatedByMutation = false,
  }) {
    if (completedNavigationEpoch != _navigationEpoch) return;

    final hadDeferredCapture = _hasDeferredMutationCapture;
    _hasDeferredMutationCapture = false;
    _isNavigationBarrierActive = false;

    // Invalidated attempts share the ordinary handoff, not inspection failure.
    if (navigationCaptureProducedLom || invalidatedByMutation) {
      if (!navigationCaptureCoveredLatestMutation && _isRunning) {
        _scheduleDebouncedCapture(restart: false);
      }
      return;
    }

    if (!hadDeferredCapture || !_isRunning) {
      return;
    }

    /// A failed navigation capture releases the barrier before giving deferred
    /// dirty work one fail-open post-frame attempt.
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
