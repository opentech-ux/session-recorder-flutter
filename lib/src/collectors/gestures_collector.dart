import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/collectors/gesture/double_tap_tracker.dart';
import 'package:session_recorder_flutter/src/collectors/gesture/gesture_sampling.dart';
import 'package:session_recorder_flutter/src/collectors/gesture/pinch_session.dart';
import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';
import 'package:session_recorder_flutter/src/utils/recorder_callback.dart';

/// Detects and records tap, double-tap, long-press, drag, and pinch gestures.
class GestureCollector {
  final SessionRecorderEngineInternal _engine;
  final Rect? Function() _viewportProvider;
  late final DoubleTapTracker _doubleTapTracker;

  GestureCollector({
    SessionRecorderEngineInternal? engine,
    required Rect? Function() viewportProvider,
  })  : _engine = engine ?? SessionRecorder.engine,
        _viewportProvider = viewportProvider {
    _doubleTapTracker = DoubleTapTracker(
      recordAction: _engine.context.recordAction,
    );
  }

  /// Tracks main active pointers for gesture detection and movement history.
  final Map<int, PointerTrace> _pointers = {};
  final Set<int> _ignoredPointers = {};
  PinchMetricsBaseline? _candidatePinchBaseline;
  PinchSession? _pinchSession;

  /// Called when a pointer first touches the screen.
  void onPointerDown(PointerDownEvent details) {
    _runPointerCallback(
      'pointer down',
      details.pointer,
      () => _onPointerDown(details),
    );
  }

  void _onPointerDown(PointerDownEvent details) {
    final pointer = details.pointer;

    /// Physical contact ordering includes contacts that gesture recognition
    /// later ignores; double-tap matching depends on that complete ordering.
    final downOrder = _doubleTapTracker.registerPointerDown();
    final pinchSession = _pinchSession;
    if (pinchSession?.hasActiveTrack(pointer) ?? false) return;

    final viewport = _viewportProvider() ?? pinchSession?.viewport;
    if (viewport == null) {
      _ignoredPointers.add(pointer);
      return;
    }

    /// Only a real Down creates a trace; additional contacts inherit the oldest
    /// interaction's frozen LOM state instead of resolving a newer snapshot.
    final hasActivePointers =
        _pointers.isNotEmpty || _ignoredPointers.isNotEmpty;
    final oldestPointer = _oldestActivePointer();
    final ({String lomRef, bool isResolved}) lomState;

    if (pinchSession != null) {
      lomState = (
        lomRef: pinchSession.lomRef,
        isResolved: pinchSession.isLomStateResolved,
      );
    } else if (hasActivePointers) {
      lomState = (
        lomRef: oldestPointer?.lomRef ?? _engine.context.currentLomRef ?? '',
        isResolved: oldestPointer?.isLomStateResolved ?? false,
      );
    } else {
      lomState = _engine.context.resolveLomStateForPointerDown();
    }

    _startPointerTrace(
      pointer,
      details.position,
      viewport: viewport,
      lomRef: lomState.lomRef,
      isLomStateResolved: lomState.isResolved,
      downOrder: downOrder,
    );

    if (_ignoredPointers.contains(pointer)) return;

    final pointerTrace = _pointers[pointer];
    if (pinchSession != null && pointerTrace != null) {
      _joinPinchSession(pointerTrace);
      return;
    }

    _updateCandidatePinchBaseline();
  }

  /// Called whenever the pointer moves across the screen.
  void onPointerMove(PointerMoveEvent details) {
    _runPointerCallback(
      'pointer move',
      details.pointer,
      () => _onPointerMove(details),
    );
  }

  void _onPointerMove(PointerMoveEvent details) {
    final pointer = details.pointer;
    final position = details.position;

    if (_ignoredPointers.contains(pointer)) return;

    final pointerTrace = _pointers[pointer];
    final pinchSession = _pinchSession;

    if (pinchSession != null) {
      // During pinch, only an already-active track may recover a missing
      // PointerTrace. An unrelated Move cannot join the gesture.
      if (!pinchSession.hasActiveTrack(pointer)) return;

      final viewport = _viewportProvider() ??
          (pointerTrace != null && !pointerTrace.isEmpty
              ? pointerTrace.last.viewport
              : pinchSession.viewport);
      if (pointerTrace != null) {
        pointerTrace.add(position, viewport: viewport);
        pointerTrace.setType(GesturesType.pinch);
        pinchSession.move(pointer, pointerTrace.last);
      } else {
        pinchSession.move(
          pointer,
          TimedPosition(
            position,
            viewport: viewport,
            lomRef: pinchSession.lomRef,
          ),
        );
      }
      return;
    }

    if (pointerTrace == null) {
      // Orphan moves are ignored instead of being promoted into gesture
      // candidates. A later real PointerDown may establish a fresh trace for
      // that pointer id.
      _ignoredPointers.add(pointer);
      return;
    }

    if (pointerTrace.isEmpty) {
      _updateCandidatePinchBaseline();
      return;
    }

    final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
    pointerTrace.add(position, viewport: viewport);
    final qualifyingPosition = pointerTrace.last;
    var currentTrace = pointerTrace;

    /// These transitions transfer sample ownership once; resolving a related
    /// pending tap prevents the same contact history from remaining tap-owned.
    if (currentTrace.type == GesturesType.longPress &&
        currentTrace.distance >= touchSlop) {
      /// Long-press is emitted once before the phase split; the new drag-only
      /// trace cannot later emit a tap or another long-press.
      _emitLongPressAction(currentTrace);
      _pointers[currentTrace.pointer] = currentTrace.splitForTransition(
        newType: GesturesType.drag,
        isPostTransitionDragOnly: true,
      );
      // Re-read after the split so later phase logic never uses a stale
      // trace from the completed long-press phase.
      currentTrace = _pointers[currentTrace.pointer]!;
    } else if (currentTrace.type == GesturesType.tap &&
        currentTrace.distance >= touchSlop) {
      if (!currentTrace.isPostTransitionDragOnly) {
        _doubleTapTracker.resolveRelatedPendingBeforeNonTap(currentTrace);
      }

      currentTrace.setType(GesturesType.drag);
    } else if (currentTrace.type == GesturesType.tap &&
        !currentTrace.isPostTransitionDragOnly &&
        currentTrace.distance <= touchSlop &&
        currentTrace.duration >= longPressTimeout) {
      _doubleTapTracker.resolveRelatedPendingBeforeNonTap(currentTrace);
      currentTrace.setType(GesturesType.longPress);
    }

    var qualifiesForPinch = false;
    // Candidate geometry is evaluated only until the pinch session starts.
    if (_pointers.length >= 2 && _candidatePinchBaseline != null) {
      qualifiesForPinch = MathUtils.evaluatePinchGesture(
        _pointers,
        _candidatePinchBaseline!,
      );
    }

    if (qualifiesForPinch) {
      _startPinchSession(currentTrace, qualifyingPosition: qualifyingPosition);
    }
  }

  /// Called whenever the pointer cancels on the screen (e.g. a phone call).
  void onPointerCancel(PointerCancelEvent details) {
    _runPointerCallback(
      'pointer cancel',
      details.pointer,
      () => _onPointerCancel(details),
    );
  }

  void _onPointerCancel(PointerCancelEvent details) {
    final pointer = details.pointer;
    _ignoredPointers.remove(pointer);
    final pointerTrace = _pointers[pointer];
    final pinchSession = _pinchSession;

    if (pinchSession != null) {
      final cancelTimestamp = DateTime.now().millisecondsSinceEpoch;
      final didCloseTrack = pinchSession.pointerCancel(
        pointer,
        cancelTimestamp,
      );
      _pointers.remove(pointer);
      if (didCloseTrack) _finishPinchIfNeeded(cancelTimestamp);
      return;
    }

    if (pointerTrace != null &&
        !pointerTrace.isEmpty &&
        !pointerTrace.isPostTransitionDragOnly &&
        pointerTrace.type == GesturesType.tap) {
      _doubleTapTracker.resolveRelatedPendingBeforeNonTap(pointerTrace);
    }

    _pointers.remove(pointer);

    if (pointerTrace != null &&
        !pointerTrace.isEmpty &&
        pointerTrace.type == GesturesType.drag) {
      _emitDragEvents(pointerTrace);
    }

    _updateCandidatePinchBaseline();
  }

  /// Forced shutdown when the collection is interrupted.
  void forceRecordCollector({bool preservePendingTaps = false}) {
    if (!runRecorderCallback('gesture drain', () {
      _forceRecordCollector(preservePendingTaps: preservePendingTaps);
    })) {
      _pointers.clear();
      _ignoredPointers.clear();
      _pinchSession = null;
      _candidatePinchBaseline = null;
    }
  }

  void _forceRecordCollector({bool preservePendingTaps = false}) {
    // Terminal drains flush completed taps first. Navigation preserves them,
    // including while an active trace is finalized below.
    if (!preservePendingTaps) _doubleTapTracker.drain();

    if (_pinchSession != null) {
      _finishPinchSession(
        DateTime.now().millisecondsSinceEpoch,
        preserveSurvivor: false,
      );
      _pointers.clear();
      _candidatePinchBaseline = null;
      _ignoredPointers.clear();
      return;
    }

    if (_pointers.isEmpty) {
      _candidatePinchBaseline = null;
      _ignoredPointers.clear();
      return;
    }

    for (final pointer in _pointers.values) {
      if (pointer.isEmpty) continue;
      _drainPointerTrace(pointer, preservePendingTaps: preservePendingTaps);
    }

    _pointers.clear();
    _candidatePinchBaseline = null;
    _ignoredPointers.clear();
  }

  /// Emit any valid gesture in progress before a system interrupt.
  void _drainPointerTrace(
    PointerTrace pointer, {
    bool preservePendingTaps = false,
  }) {
    if (pointer.type == GesturesType.drag) {
      _emitDragEvents(pointer);
    } else if (pointer.isPostTransitionDragOnly) {
      if (pointer.distance >= touchSlop) {
        pointer.setType(GesturesType.drag);
        _emitDragEvents(pointer);
      }
    } else if (pointer.type == GesturesType.longPress ||
        (pointer.duration >= longPressTimeout &&
            pointer.distance < touchSlop)) {
      _evaluateLongPress(pointer, resolvePendingTaps: !preservePendingTaps);
    } else if (pointer.distance >= touchSlop) {
      _evaluateDrag(pointer, resolvePendingTaps: !preservePendingTaps);
    }
  }

  /// Starts a trace with its first real position.
  void _startPointerTrace(
    int pointer,
    Offset position, {
    required Rect viewport,
    required String lomRef,
    required bool isLomStateResolved,
    required int downOrder,
  }) {
    _ignoredPointers.remove(pointer);
    _pointers[pointer] = PointerTrace(
      pointer: pointer,
      lomRef: lomRef,
      isLomStateResolved: isLomStateResolved,
      downOrder: downOrder,
      type: GesturesType.tap,
    )..add(position, viewport: viewport);
  }

  PointerTrace? _oldestActivePointer() {
    PointerTrace? oldest;

    for (final trace in _pointers.values) {
      if (trace.isEmpty) continue;
      if (oldest == null ||
          trace.firstTimestamp < oldest.firstTimestamp ||
          (trace.firstTimestamp == oldest.firstTimestamp &&
              trace.pointer < oldest.pointer)) {
        oldest = trace;
      }
    }

    return oldest;
  }

  PinchMetricsBaseline _buildCandidatePinchBaseline() {
    return PinchMetricsBaseline(
      initialPositions: _pointers.map(
        (key, pointer) => MapEntry(key, pointer.lastPosition),
      ),
      centroid: MathUtils.getCentroid(_pointers),
      avgDistance: MathUtils.getAverageDistance(_pointers),
    );
  }

  void _updateCandidatePinchBaseline() {
    if (_pinchSession != null) return;

    final emptyPointers =
        _pointers.entries.where((entry) => entry.value.isEmpty).toList();
    for (final entry in emptyPointers) {
      _pointers.remove(entry.key);
      _ignoredPointers.add(entry.key);
    }

    if (_pointers.length >= 2) {
      _candidatePinchBaseline = _buildCandidatePinchBaseline();
    } else {
      _candidatePinchBaseline = null;
    }
  }

  void _joinPinchSession(PointerTrace pointerTrace) {
    final pinchSession = _pinchSession;
    if (pinchSession == null || pointerTrace.isEmpty) return;

    final didJoin = pinchSession.join(
      pointerId: pointerTrace.pointer,
      entryTimestamp: pointerTrace.lastTimestamp,
      initialPosition: pointerTrace.last,
    );
    if (!didJoin) return;

    pointerTrace.setType(GesturesType.pinch);
    _candidatePinchBaseline = null;
  }

  void _startPinchSession(
    PointerTrace qualifyingTrace, {
    required TimedPosition qualifyingPosition,
  }) {
    if (_pinchSession != null || qualifyingTrace.isEmpty) return;

    /// Recognizing a non-tap gesture finalizes any compatible pending tap before
    /// pinch takes exclusive ownership of the qualifying and later samples.
    for (final pointerTrace in _pointers.values) {
      if (!pointerTrace.isEmpty &&
          !pointerTrace.isPostTransitionDragOnly &&
          pointerTrace.type == GesturesType.tap) {
        _doubleTapTracker.resolveRelatedPendingBeforeNonTap(pointerTrace);
      }
    }

    final oldestPointer = _oldestActivePointer();
    final pinchSession = PinchSession(
      startTimestamp: qualifyingPosition.timestamp,
      viewport: qualifyingPosition.viewport,
      lomRef: oldestPointer?.lomRef ?? qualifyingTrace.lomRef,
      isLomStateResolved: oldestPointer?.isLomStateResolved ??
          qualifyingTrace.isLomStateResolved,
    );
    _pinchSession = pinchSession;

    for (final pointerTrace in _pointers.values) {
      if (pointerTrace.isEmpty) continue;
      final entryPosition = pointerTrace.pointer == qualifyingTrace.pointer
          ? qualifyingPosition
          : TimedPosition(
              pointerTrace.lastPosition,
              viewport: pointerTrace.last.viewport,
              lomRef: pointerTrace.lomRef,
            );
      pinchSession.join(
        pointerId: pointerTrace.pointer,
        entryTimestamp: qualifyingPosition.timestamp,
        initialPosition: entryPosition,
      );
    }
    _candidatePinchBaseline = null;

    for (final pointerTrace in _pointers.values.toList()) {
      if (pointerTrace.type == GesturesType.drag) {
        if (pointerTrace.pointer == qualifyingTrace.pointer) {
          /// The qualifying physical sample belongs to pinch, not both phases;
          /// the temporary removal lets the preceding drag end before it.
          final qualifyingSample = pointerTrace.positions.removeLast();
          if (!pointerTrace.isEmpty && pointerTrace.distance >= touchSlop) {
            _emitDragEvents(pointerTrace);
          }
          pointerTrace.positions.add(qualifyingSample);
        } else {
          _emitDragEvents(pointerTrace);
        }

        _pointers[pointerTrace.pointer] = pointerTrace.splitForTransition(
          newType: GesturesType.pinch,
        );
        continue;
      }

      pointerTrace.setType(GesturesType.pinch);
    }
  }

  void _finishPinchIfNeeded(int timestamp) {
    final pinchSession = _pinchSession;
    if (pinchSession == null || pinchSession.activePointerCount >= 2) return;

    _finishPinchSession(timestamp, preserveSurvivor: true);
  }

  void _finishPinchSession(int endTimestamp, {required bool preserveSurvivor}) {
    final pinchSession = _pinchSession;
    if (pinchSession == null) return;

    final survivorId = pinchSession.soleActivePointerId;
    final survivorPosition =
        survivorId == null ? null : pinchSession.lastPositionFor(survivorId);
    final survivorTrace = survivorId == null ? null : _pointers[survivorId];
    final event = pinchSession.finish(endTimestamp);

    _pinchSession = null;
    _candidatePinchBaseline = null;
    if (event != null) _engine.context.recordExploration(event);

    if (!preserveSurvivor || survivorId == null || survivorPosition == null) {
      return;
    }

    // The survivor starts a new transition phase at the pinch exit anchor. It
    // can only qualify as a later drag, never as tap or long-press.
    _pointers[survivorId] = PointerTrace(
      pointer: survivorId,
      lomRef: survivorTrace?.lomRef ?? pinchSession.lomRef,
      isLomStateResolved:
          survivorTrace?.isLomStateResolved ?? pinchSession.isLomStateResolved,
      downOrder: survivorTrace?.downOrder ?? 0,
      type: GesturesType.tap,
      isPostTransitionDragOnly: true,
    )..add(survivorPosition.position, viewport: survivorPosition.viewport);
  }

  /// Called when the pointer is lifted from the screen.
  void onPointerUp(PointerUpEvent details) {
    _runPointerCallback(
      'pointer up',
      details.pointer,
      () => _onPointerUp(details),
    );
  }

  void _runPointerCallback(
      String operation, int pointer, VoidCallback callback) {
    final hadPinchSession = _pinchSession != null;
    if (runRecorderCallback(operation, callback)) return;

    // Abandon only the failed contact, or its shared pinch. Completed pending
    // taps remain owned by DoubleTapTracker and are not emitted again.
    if (hadPinchSession || _pinchSession != null) {
      _pointers.clear();
      _pinchSession = null;
    } else {
      _pointers.remove(pointer);
    }
    _ignoredPointers.remove(pointer);
    _candidatePinchBaseline = null;
  }

  void _onPointerUp(PointerUpEvent details) {
    final pointer = details.pointer;

    // Up advances the same physical contact ordering even when the pointer was
    // ignored or its trace is unavailable.
    final upOrder = _doubleTapTracker.registerPointerUp();
    _ignoredPointers.remove(pointer);
    final pointerTrace = _pointers[pointer];
    final pinchSession = _pinchSession;

    if (pinchSession != null) {
      if (!pinchSession.hasActiveTrack(pointer)) {
        _pointers.remove(pointer);
        return;
      }

      final viewport = _viewportProvider() ??
          (pointerTrace != null && !pointerTrace.isEmpty
              ? pointerTrace.last.viewport
              : pinchSession.viewport);
      final TimedPosition terminalPosition;
      if (pointerTrace != null) {
        pointerTrace.add(details.position, viewport: viewport);
        terminalPosition = pointerTrace.last;
      } else {
        terminalPosition = TimedPosition(
          details.position,
          viewport: viewport,
          lomRef: pinchSession.lomRef,
        );
      }

      pinchSession.pointerUp(pointer, terminalPosition);
      _pointers.remove(pointer);
      _finishPinchIfNeeded(terminalPosition.timestamp);
      return;
    }

    if (pointerTrace == null) return;
    _pointers.remove(pointer);

    if (pointerTrace.isEmpty) {
      _updateCandidatePinchBaseline();
      return;
    }

    final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
    pointerTrace.add(details.position, viewport: viewport);

    // A stale pinch trace cannot produce an independent pinch event.
    if (pointerTrace.type == GesturesType.pinch) {
      _updateCandidatePinchBaseline();
      return;
    }

    _updateCandidatePinchBaseline();

    if (pointerTrace.isPostTransitionDragOnly) {
      if (pointerTrace.type == GesturesType.drag ||
          pointerTrace.distance >= touchSlop) {
        _evaluateDrag(pointerTrace);
      }
      return;
    }

    /// A recognized drag stays drag even when Up returns near its origin.
    if (pointerTrace.type == GesturesType.drag) {
      _evaluateDrag(pointerTrace);
      return;
    }

    if (pointerTrace.duration >= longPressTimeout &&
        pointerTrace.distance < touchSlop) {
      _evaluateLongPress(pointerTrace);
      return;
    }

    if (pointerTrace.distance >= touchSlop) {
      _evaluateDrag(pointerTrace);
      return;
    }

    pointerTrace.setType(GesturesType.tap);
    _doubleTapTracker.completeTap(pointerTrace, upOrder: upOrder);
  }

  void _evaluateDrag(
    PointerTrace pointerTrace, {
    bool resolvePendingTaps = true,
  }) {
    if (resolvePendingTaps &&
        pointerTrace.type == GesturesType.tap &&
        !pointerTrace.isPostTransitionDragOnly) {
      _doubleTapTracker.resolveRelatedPendingBeforeNonTap(pointerTrace);
    }
    pointerTrace.setType(GesturesType.drag);
    for (final exploration in _buildDragEvents(pointerTrace)) {
      _engine.context.recordExploration(exploration);
    }
  }

  void _evaluateLongPress(
    PointerTrace pointerTrace, {
    bool resolvePendingTaps = true,
  }) {
    if (resolvePendingTaps &&
        pointerTrace.type == GesturesType.tap &&
        !pointerTrace.isPostTransitionDragOnly) {
      _doubleTapTracker.resolveRelatedPendingBeforeNonTap(pointerTrace);
    }
    pointerTrace.setType(GesturesType.longPress);
    _engine.context.recordAction(_buildLongPressAction(pointerTrace));
  }

  void _emitDragEvents(PointerTrace pointerTrace) {
    for (final exploration in _buildDragEvents(pointerTrace)) {
      _engine.context.recordExploration(exploration);
    }
  }

  void _emitLongPressAction(PointerTrace pointerTrace) {
    _engine.context.recordAction(_buildLongPressAction(pointerTrace));
  }

  LongPressActionEvent _buildLongPressAction(PointerTrace pointer) {
    final firstPosition = pointer.first;
    return LongPressActionEvent(
      timestampRelative: firstPosition.timestamp,
      duration: pointer.duration,
      viewport: firstPosition.viewport,
      position: firstPosition.position,
      lomRef: firstPosition.lomRef,
    );
  }

  List<DragExplorationEvent> _buildDragEvents(PointerTrace pointer) {
    if (pointer.type != GesturesType.drag || pointer.positions.isEmpty) {
      return [];
    }

    return sampleTimedPositions(pointer.positions)
        .map(
          (position) => DragExplorationEvent(
            timestamp: position.timestamp,
            pointer: pointer.pointer,
            viewport: position.viewport,
            position: position.position,
            lomRef: position.lomRef,
          ),
        )
        .toList();
  }

  /// Exposes sampling for focused regression tests.
  List<TimedPosition> samplePositionsForTest(
    List<TimedPosition> positions, {
    int timestampThresholdMs = 50,
  }) {
    return sampleTimedPositions(
      positions,
      timestampThresholdMs: timestampThresholdMs,
    );
  }
}
