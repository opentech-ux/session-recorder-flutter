import 'dart:async';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

/// Detects and records tap, double-tap, long-press, drag, and pinch gestures.
class GestureCollector {
  final SessionRecorderEngineInternal _engine;
  final Rect? Function() _viewportProvider;

  GestureCollector({
    SessionRecorderEngineInternal? engine,
    required Rect? Function() viewportProvider,
  }) : _engine = engine ?? SessionRecorder.engine,
       _viewportProvider = viewportProvider;

  /// Tracks main active pointers for gesture detection and movement history
  final Map<int, PointerTrace> _pointers = {};
  final Set<int> _ignoredPointers = {};
  final List<_PendingTap> _pendingTaps = [];
  Timer? _doubleTapTimer;
  int? _doubleTapDeadline;
  int _contactOrder = 0;
  PinchMetricsBaseline? _candidatePinchBaseline;
  _ActivePinchSession? _activePinch;

  /// Called when a pointer first touches the screen.
  void onPointerDown(PointerDownEvent details) {
    final int pointer = details.pointer;
    final downOrder = ++_contactOrder;
    final activePinch = _activePinch;
    final viewport = _viewportProvider() ?? activePinch?.viewport;
    if (viewport == null) {
      _ignoredPointers.add(pointer);
      return;
    }

    final hasActivePointers =
        _pointers.isNotEmpty || _ignoredPointers.isNotEmpty;
    final oldestPointer = _oldestActivePointer();
    final ({String lomRef, bool isResolved}) lomState;

    if (activePinch != null) {
      lomState = (
        lomRef: activePinch.lomRef,
        isResolved: oldestPointer?.isLomStateResolved ?? false,
      );
    } else if (hasActivePointers) {
      lomState = (
        lomRef:
            oldestPointer?.lomRef ?? _engine.context.currentLomRef ?? '',
        isResolved: oldestPointer?.isLomStateResolved ?? false,
      );
    } else {
      lomState = _engine.context.resolveLomStateForPointerDown();
    }

    /// Add the first [PointerTrace]
    addPointer(
      pointer,
      details.position,
      viewport: viewport,
      lomRef: lomState.lomRef,
      isLomStateResolved: lomState.isResolved,
      downOrder: downOrder,
    );

    if (_ignoredPointers.contains(pointer)) return;

    final pointerTrace = _pointers[pointer];
    if (activePinch != null && pointerTrace != null) {
      _joinActivePinch(pointerTrace);
      return;
    }

    _updateCandidatePinchBaseline();
  }

  /// Called whenever the pointer moves across the screen.
  ///
  /// Compares the current position and movement delta with the initial data
  /// from [onPointerDown] to determine whether the gesture still qualifies
  /// as a tap or if it should be treated for another gesture.
  ///
  /// This is where movement thresholds or gesture cancellation logic
  /// (e.g. “no longer a tap”) are typically evaluated.
  ///
  /// Doing nothing if `_didScroll` is [true].
  ///
  void onPointerMove(PointerMoveEvent details) {
    final int pointer = details.pointer;
    final Offset position = details.position;

    if (_ignoredPointers.contains(pointer)) return;

    final PointerTrace? pointerTrace = _pointers[pointer];

    /// If for some reason the current `pointer` not exist in `_pointers`, we
    /// add it
    if (pointerTrace == null) {
      /// Add the [PointerTrace]
      final activePinch = _activePinch;
      addPointer(
        pointer,
        position,
        viewport: activePinch?.viewport,
        lomRef: activePinch?.lomRef,
      );

      final recoveredTrace = _pointers[pointer];
      if (activePinch != null && recoveredTrace != null) {
        _joinActivePinch(recoveredTrace);
      } else {
        _updateCandidatePinchBaseline();
      }

      return;
    }

    if (pointerTrace.isEmpty) {
      _updateCandidatePinchBaseline();
      return;
    }

    final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
    pointerTrace.add(
      position,
      viewport: viewport,
    );

    final activePinch = _activePinch;
    if (activePinch != null) {
      final track = activePinch.tracks[pointer];
      if (track == null) {
        _joinActivePinch(pointerTrace);
      } else {
        pointerTrace.setType(GesturesType.pinch);
        track.positions.add(pointerTrace.last);
      }

      if (_pointers.length >= 2) {
        MathUtils.evaluatePinchGesture(_pointers, activePinch.baseline);
      }
      return;
    }

    if (pointerTrace.type != GesturesType.pinch &&
        pointerTrace.distance >= touchSlop) {
      // * SPLIT LONG PRESS
      final bool isAlreadyLongPress =
          pointerTrace.type == GesturesType.longPress;

      if (isAlreadyLongPress) {
        _emitAction(pointerTrace);

        _pointers[pointerTrace.pointer] = pointerTrace.splitForTransition(
          newType: GesturesType.drag,
          isDragOnly: true,
        );
      } else {
        _resolvePendingTapForTrace(pointerTrace);
        pointerTrace.setType(GesturesType.drag);
      }
    } else if (pointerTrace.type != GesturesType.pinch &&
        !pointerTrace.isDragOnly &&
        pointerTrace.distance <= touchSlop &&
        pointerTrace.duration >= longPressTimeout) {
      _resolvePendingTapForTrace(pointerTrace);
      pointerTrace.setType(GesturesType.longPress);
    }

    bool isScaling = false;

    if (_pointers.length >= 2 && _candidatePinchBaseline != null) {
      isScaling = MathUtils.evaluatePinchGesture(
        _pointers,
        _candidatePinchBaseline!,
      );
    }

    if (isScaling) _startActivePinch(pointerTrace);
  }

  /// Called whenever the pointer cancels in the screen (e.g. a phone call).
  void onPointerCancel(PointerCancelEvent details) {
    final pointer = details.pointer;
    _ignoredPointers.remove(pointer);
    final pointerTrace = _pointers[pointer];

    final activePinch = _activePinch;
    if (activePinch != null && pointerTrace != null) {
      final cancelTimestamp = DateTime.now().millisecondsSinceEpoch;
      activePinch.tracks[pointer]?.exitTimestamp = cancelTimestamp;
      _pointers.remove(pointer);
      _continueOrFinishActivePinch(cancelTimestamp);
      return;
    }

    if (pointerTrace != null &&
        !pointerTrace.isEmpty &&
        !pointerTrace.isDragOnly &&
        pointerTrace.type == GesturesType.tap) {
      _resolvePendingTapForTrace(pointerTrace);
    }

    _pointers.remove(pointer);

    if (pointerTrace != null) {
      if (!pointerTrace.isEmpty &&
          pointerTrace.type == GesturesType.drag) {
        _emitExplorations(pointerTrace);
      }
    }

    _updateCandidatePinchBaseline();
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    _drainPendingTaps();

    if (_activePinch != null) {
      _finishActivePinch(
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

    for (var p in _pointers.values) {
      if (p.isEmpty) continue;
      _evaluatePointer(p);
    }

    _pointers.clear();
    _candidatePinchBaseline = null;
    _ignoredPointers.clear();
  }

  /// Emit any valid gesture that is in progress to the record before
  /// the pointer is destroyed by a system interrupt.
  void _evaluatePointer(PointerTrace p) {
    if (p.type == GesturesType.drag) {
      _emitExplorations(p);
    } else if (p.isDragOnly) {
      if (p.distance >= touchSlop) {
        p.setType(GesturesType.drag);
        _emitExplorations(p);
      }
    } else if (p.type == GesturesType.longPress ||
        (p.duration >= longPressTimeout && p.distance < touchSlop)) {
      _evaluateLongPress(p);
    } else if (p.distance >= touchSlop) {
      _evaluateDrag(p);
    }
  }

  /// Add the first `[PointerTrace]` with their first `[TimedPosition]`.
  ///
  /// Set `[GesturesType.tap]` type by __default__.
  void addPointer(
    int pointer,
    Offset position, {
    GesturesType type = GesturesType.tap,
    Rect? viewport,
    String? lomRef,
    bool? isLomStateResolved,
    int? downOrder,
  }) {
    final resolvedViewport = viewport ?? _viewportProvider();
    if (resolvedViewport == null) {
      _ignoredPointers.add(pointer);
      return;
    }

    _ignoredPointers.remove(pointer);
    final oldestPointer = _oldestActivePointer();
    final resolvedLomRef =
        lomRef ?? oldestPointer?.lomRef ?? _engine.context.currentLomRef ?? '';

    _pointers[pointer] = PointerTrace(
      pointer: pointer,
      lomRef: resolvedLomRef,
      isLomStateResolved:
          isLomStateResolved ?? oldestPointer?.isLomStateResolved ?? false,
      downOrder: downOrder ?? _contactOrder,
      type: type,
    )
      ..add(
        position,
        viewport: resolvedViewport,
      );
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

  PinchMetricsBaseline _buildPinchBaseline() {
    return PinchMetricsBaseline(
      initialPositions: _pointers.map(
        (key, pointer) => MapEntry(key, pointer.lastPosition),
      ),
      centroid: MathUtils.getCentroid(_pointers),
      avgDistance: MathUtils.getAverageDistance(_pointers),
    );
  }

  void _updateCandidatePinchBaseline() {
    final emptyPointers = _pointers.entries
        .where((entry) => entry.value.isEmpty)
        .toList();

    final removedAt = DateTime.now().millisecondsSinceEpoch;
    for (final entry in emptyPointers) {
      _pointers.remove(entry.key);
      _ignoredPointers.add(entry.key);
      _activePinch?.tracks[entry.key]?.exitTimestamp = removedAt;
    }

    if (_activePinch != null) {
      _continueOrFinishActivePinch(removedAt);
      return;
    }

    if (_pointers.length >= 2) {
      _candidatePinchBaseline = _buildPinchBaseline();
    } else {
      _candidatePinchBaseline = null;
    }
  }

  void _joinActivePinch(PointerTrace pointerTrace) {
    final activePinch = _activePinch;
    if (activePinch == null || pointerTrace.isEmpty) return;

    pointerTrace.setType(GesturesType.pinch);
    activePinch.tracks[pointerTrace.pointer] = _ActivePinchTrack(
      pointerId: pointerTrace.pointer,
      entryTimestamp: pointerTrace.lastTimestamp,
      positions: [pointerTrace.last],
    );
    _candidatePinchBaseline = null;

    if (_pointers.length >= 2) {
      activePinch.baseline = _buildPinchBaseline();
    }
  }

  void _startActivePinch(PointerTrace qualifyingPointer) {
    if (_activePinch != null || qualifyingPointer.isEmpty) return;

    for (final pointerTrace in _pointers.values) {
      if (!pointerTrace.isEmpty &&
          !pointerTrace.isDragOnly &&
          pointerTrace.type == GesturesType.tap) {
        _resolvePendingTapForTrace(pointerTrace);
      }
    }

    final startPosition = qualifyingPointer.last;
    final oldestPointer = _oldestActivePointer();
    final tracks = <int, _ActivePinchTrack>{};

    for (final pointerTrace in _pointers.values) {
      if (pointerTrace.isEmpty) continue;
      final entryPosition = pointerTrace.pointer == qualifyingPointer.pointer
          ? startPosition
          : TimedPosition(
              pointerTrace.lastPosition,
              viewport: pointerTrace.last.viewport,
              lomRef: pointerTrace.lomRef,
            );
      tracks[pointerTrace.pointer] = _ActivePinchTrack(
        pointerId: pointerTrace.pointer,
        entryTimestamp: startPosition.timestamp,
        positions: [entryPosition],
      );
    }

    _activePinch = _ActivePinchSession(
      startTimestamp: startPosition.timestamp,
      viewport: startPosition.viewport,
      lomRef: oldestPointer?.lomRef ?? qualifyingPointer.lomRef,
      tracks: tracks,
      baseline: _buildPinchBaseline(),
    );
    _candidatePinchBaseline = null;

    for (final pointerTrace in _pointers.values.toList()) {
      if (pointerTrace.type == GesturesType.drag) {
        if (pointerTrace.pointer == qualifyingPointer.pointer) {
          final qualifyingPosition = pointerTrace.positions.removeLast();
          if (!pointerTrace.isEmpty && pointerTrace.distance >= touchSlop) {
            _emitExplorations(pointerTrace);
          }
          pointerTrace.positions.add(qualifyingPosition);
        } else {
          _emitExplorations(pointerTrace);
        }

        _pointers[pointerTrace.pointer] = pointerTrace.splitForTransition(
          newType: GesturesType.pinch,
        );
      } else {
        pointerTrace.setType(GesturesType.pinch);
      }
    }
  }

  void _continueOrFinishActivePinch(int timestamp) {
    final activePinch = _activePinch;
    if (activePinch == null) return;

    if (_pointers.length >= 2) {
      activePinch.baseline = _buildPinchBaseline();
      return;
    }

    _finishActivePinch(timestamp, preserveSurvivor: true);
  }

  void _finishActivePinch(
    int endTimestamp, {
    required bool preserveSurvivor,
  }) {
    final activePinch = _activePinch;
    if (activePinch == null) return;

    for (final track in activePinch.tracks.values) {
      track.exitTimestamp ??= endTimestamp;
    }

    final tracks = activePinch.tracks.values
        .where((track) => track.positions.isNotEmpty)
        .map((track) {
          final sampledPositions = _samplePositions(track.positions);
          return PinchTrack(
            pointerId: track.pointerId,
            entryDelta: track.entryTimestamp - activePinch.startTimestamp,
            exitDelta: track.exitTimestamp! - activePinch.startTimestamp,
            positions: sampledPositions
                .map((position) => position.position)
                .toList(),
          );
        })
        .toList();

    _activePinch = null;
    _candidatePinchBaseline = null;

    if (tracks.isNotEmpty) {
      _engine.context.recordExploration(
        PinchExplorationEvent(
          timestamp: activePinch.startTimestamp,
          viewport: activePinch.viewport,
          endTimestamp: endTimestamp,
          tracks: tracks,
          lomRef: activePinch.lomRef,
        ),
      );
    }

    if (preserveSurvivor && _pointers.length == 1) {
      final remainingPointer = _pointers.values.single;
      if (!remainingPointer.isEmpty) {
        _pointers[remainingPointer.pointer] =
            remainingPointer.splitForTransition(
              newType: GesturesType.tap,
              isDragOnly: true,
            );
      }
    }
  }

  /// Called when the pointer is lifted from the screen.
  ///
  /// Finalizes the gesture logic based on previous movement analysis.
  void onPointerUp(PointerUpEvent details) {
    final int pointer = details.pointer;
    final upOrder = ++_contactOrder;
    _ignoredPointers.remove(pointer);
    final PointerTrace? pointerTrace = _pointers[pointer];

    if (pointerTrace == null) return;

    final activePinch = _activePinch;
    if (activePinch != null) {
      int endTimestamp;
      if (pointerTrace.isEmpty) {
        endTimestamp = DateTime.now().millisecondsSinceEpoch;
      } else {
        final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
        pointerTrace.add(
          details.position,
          viewport: viewport,
        );

        final track = activePinch.tracks[pointer];
        if (track == null) {
          _joinActivePinch(pointerTrace);
        } else {
          track.positions.add(pointerTrace.last);
        }
        endTimestamp = pointerTrace.lastTimestamp;
      }

      activePinch.tracks[pointer]?.exitTimestamp = endTimestamp;
      _pointers.remove(pointer);
      _continueOrFinishActivePinch(endTimestamp);
      return;
    }

    _pointers.remove(pointer);

    if (pointerTrace.isEmpty) {
      _updateCandidatePinchBaseline();
      return;
    }

    final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
    pointerTrace.add(
      details.position,
      viewport: viewport,
    );

    // A stale pinch trace cannot produce an independent pinch event.
    if (pointerTrace.type == GesturesType.pinch) {
      _updateCandidatePinchBaseline();
      return;
    }

    _updateCandidatePinchBaseline();

    // A transition trace cannot become a tap or long press. A long-press drag
    // is already typed as drag, while a post-pinch trace must first move far
    // enough from its transition anchor.
    if (pointerTrace.isDragOnly) {
      if (pointerTrace.type == GesturesType.drag ||
          pointerTrace.distance >= touchSlop) {
        _evaluateDrag(pointerTrace);
      }

      return;
    }

    // * LONG PRESS
    if (pointerTrace.duration >= longPressTimeout &&
        pointerTrace.distance < touchSlop) {
      _evaluateLongPress(pointerTrace);

      return;
    }

    // * DRAG
    if (pointerTrace.distance >= touchSlop) {
      _evaluateDrag(pointerTrace);

      return;
    }

    // * TAP
    pointerTrace.setType(GesturesType.tap);

    _evaluateTap(pointerTrace, upOrder: upOrder);
  }

  void _evaluateTap(PointerTrace pointerTrace, {required int upOrder}) {
    final current = _PendingTap(
      downTimestamp: pointerTrace.firstTimestamp,
      upTimestamp: pointerTrace.lastTimestamp,
      downOrder: pointerTrace.downOrder,
      upOrder: upOrder,
      actionPosition: pointerTrace.firstPosition,
      terminalPosition: pointerTrace.lastPosition,
      viewport: pointerTrace.first.viewport,
      lomRef: pointerTrace.lomRef,
      isLomStateResolved: pointerTrace.isLomStateResolved,
    );

    _expirePendingTaps(current.upTimestamp);

    final matchIndex = _findBestPendingTapIndex(
      downTimestamp: current.downTimestamp,
      downOrder: current.downOrder,
      matchTimestamp: current.upTimestamp,
      terminalPosition: current.terminalPosition,
      viewport: current.viewport,
      lomRef: current.lomRef,
      isLomStateResolved: current.isLomStateResolved,
    );

    if (matchIndex != null) {
      final first = _pendingTaps.removeAt(matchIndex);
      _scheduleDoubleTapTimer();
      _emitDoubleTap(first, current);
      return;
    }

    _pendingTaps.add(current);
    _scheduleDoubleTapTimer();
  }

  int? _findBestPendingTapIndex({
    required int downTimestamp,
    required int downOrder,
    required int matchTimestamp,
    required Offset terminalPosition,
    required Rect viewport,
    required String lomRef,
    required bool isLomStateResolved,
  }) {
    int? bestIndex;
    double? bestDistance;
    int? bestUpOrder;

    for (var i = 0; i < _pendingTaps.length; i++) {
      final pending = _pendingTaps[i];
      if (downOrder <= pending.upOrder ||
          downTimestamp < pending.upTimestamp) {
        continue;
      }

      final elapsed = matchTimestamp - pending.upTimestamp;
      if (elapsed < 0 || elapsed > doubleTapTimeout.inMilliseconds) continue;
      if (viewport != pending.viewport ||
          !isLomStateResolved ||
          !pending.isLomStateResolved ||
          lomRef != pending.lomRef) {
        continue;
      }

      final distance = (terminalPosition - pending.terminalPosition).distance;
      if (distance >= doubleTapSlop) continue;

      if (bestDistance == null ||
          distance < bestDistance ||
          (distance == bestDistance && pending.upOrder > bestUpOrder!)) {
        bestIndex = i;
        bestDistance = distance;
        bestUpOrder = pending.upOrder;
      }
    }

    return bestIndex;
  }

  void _resolvePendingTapForTrace(PointerTrace pointerTrace) {
    if (pointerTrace.isEmpty || _pendingTaps.isEmpty) return;

    _expirePendingTaps(pointerTrace.lastTimestamp);
    final matchIndex = _findBestPendingTapIndex(
      downTimestamp: pointerTrace.firstTimestamp,
      downOrder: pointerTrace.downOrder,
      matchTimestamp: pointerTrace.lastTimestamp,
      terminalPosition: pointerTrace.firstPosition,
      viewport: pointerTrace.first.viewport,
      lomRef: pointerTrace.lomRef,
      isLomStateResolved: pointerTrace.isLomStateResolved,
    );
    if (matchIndex == null) return;

    final pending = _pendingTaps.removeAt(matchIndex);
    _scheduleDoubleTapTimer();
    _emitPendingTap(pending);
  }

  void _expirePendingTaps(int now) {
    if (_pendingTaps.isEmpty) return;

    final expired = <_PendingTap>[];
    _pendingTaps.removeWhere((pending) {
      final isExpired = now > pending.lastEligibleTimestamp;
      if (isExpired) expired.add(pending);
      return isExpired;
    });
    if (expired.isEmpty) return;

    _scheduleDoubleTapTimer();
    for (final pending in expired) {
      _emitPendingTap(pending);
    }
  }

  void _scheduleDoubleTapTimer() {
    if (_pendingTaps.isEmpty) {
      _cancelDoubleTapTimer();
      return;
    }

    var nextDeadline = _pendingTaps.first.expiryDeadline;
    for (var i = 1; i < _pendingTaps.length; i++) {
      final deadline = _pendingTaps[i].expiryDeadline;
      if (deadline < nextDeadline) nextDeadline = deadline;
    }

    if ((_doubleTapTimer?.isActive ?? false) &&
        _doubleTapDeadline == nextDeadline) {
      return;
    }

    _cancelDoubleTapTimer();
    final now = DateTime.now().millisecondsSinceEpoch;
    final delay = nextDeadline > now ? nextDeadline - now : 0;
    _doubleTapDeadline = nextDeadline;

    late final Timer timer;
    timer = Timer(Duration(milliseconds: delay), () {
      if (!identical(_doubleTapTimer, timer)) return;
      _doubleTapTimer = null;
      _doubleTapDeadline = null;
      _expirePendingTaps(DateTime.now().millisecondsSinceEpoch);
      _scheduleDoubleTapTimer();
    });
    _doubleTapTimer = timer;
  }

  void _cancelDoubleTapTimer() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _doubleTapDeadline = null;
  }

  void _drainPendingTaps() {
    _cancelDoubleTapTimer();
    if (_pendingTaps.isEmpty) return;

    final pendingTaps = List<_PendingTap>.of(_pendingTaps);
    _pendingTaps.clear();
    for (final pending in pendingTaps) {
      _emitPendingTap(pending);
    }
  }

  void _emitPendingTap(_PendingTap pending) {
    _engine.context.recordAction(
      TapActionEvent(
        timestampRelative: pending.downTimestamp,
        viewport: pending.viewport,
        position: pending.actionPosition,
        lomRef: pending.lomRef,
      ),
    );
  }

  void _emitDoubleTap(_PendingTap first, _PendingTap second) {
    _engine.context.recordAction(
      DoubleTapActionEvent(
        timestampRelative: first.downTimestamp,
        secondTimestamp: second.downTimestamp,
        viewport: first.viewport,
        positions: [first.actionPosition, second.actionPosition],
        lomRef: first.lomRef,
      ),
    );
  }

  void _evaluateDrag(PointerTrace pointerTrace) {
    if (pointerTrace.type != GesturesType.drag && !pointerTrace.isDragOnly) {
      _resolvePendingTapForTrace(pointerTrace);
    }
    pointerTrace.setType(GesturesType.drag);
    final explorations = _createExplorationEvent(pointerTrace);
    for (ExplorationEvent exploration in explorations) {
      _engine.context.recordExploration(exploration);
    }
  }

  void _evaluateLongPress(PointerTrace pointerTrace) {
    if (pointerTrace.type != GesturesType.longPress) {
      _resolvePendingTapForTrace(pointerTrace);
    }
    pointerTrace.setType(GesturesType.longPress);
    final action = _createActionEvent(pointerTrace);
    _engine.context.recordAction(action);
  }

  void _emitExplorations(PointerTrace pointerTrace) {
    final explorations = _createExplorationEvent(pointerTrace);
    if (explorations.isNotEmpty) {
      for (final exploration in explorations) {
        _engine.context.recordExploration(exploration);
      }
    }
  }

  void _emitAction(PointerTrace pointerTrace) {
    final action = _createActionEvent(pointerTrace);
    _engine.context.recordAction(action);
  }

  /// Creates and returns the `[ActionEvent]` object with its LOM ref.
  ///
  /// - `[TapActionEvent]`
  /// - `[LongPressActionEvent]`
  ActionEvent _createActionEvent(PointerTrace pointer) {
    final TimedPosition firstPosition = pointer.first;

    switch (pointer.type) {
      case GesturesType.longPress:
        return LongPressActionEvent(
          timestampRelative: firstPosition.timestamp,
          duration: pointer.duration,
          viewport: firstPosition.viewport,
          position: firstPosition.position,
          lomRef: firstPosition.lomRef,
        );
      default:
        return TapActionEvent(
          timestampRelative: firstPosition.timestamp,
          viewport: firstPosition.viewport,
          position: firstPosition.position,
          lomRef: firstPosition.lomRef,
        );
    }
  }

  /// Creates drag explorations from a pointer trace.
  List<ExplorationEvent> _createExplorationEvent(PointerTrace pointer) {
    if (pointer.type != GesturesType.drag) return [];
    return _getDragExploration(pointer);
  }

  /// Converts the recorded `[PointerTrace]` data into a list of `[DragExplorationEvent]`
  /// instances.
  List<DragExplorationEvent> _getDragExploration(PointerTrace pointer) {
    final List<TimedPosition> positions = pointer.positions;

    if (positions.isEmpty) return [];

    final sampledPositions = _samplePositions(positions);

    List<DragExplorationEvent> panList = List.from(
      sampledPositions.map(
        (touchDrag) => DragExplorationEvent(
          timestamp: touchDrag.timestamp,
          pointer: pointer.pointer,
          viewport: touchDrag.viewport,
          position: touchDrag.position,
          lomRef: touchDrag.lomRef,
        ),
      ),
    );

    return panList;
  }

  /// Returns a sampled version of `positions` keeping every `timestampThresholdMs` point.
  /// Always includes the first and last position to preserve start and end.
  List<TimedPosition> _samplePositions(
    List<TimedPosition> positions, {
    int timestampThresholdMs = 50,
  }) {
    if (positions.length <= 2) return positions;

    final sampled = <TimedPosition>[positions.first];
    TimedPosition lastSaved = positions.first;

    for (var i = 1; i < positions.length; i++) {
      final current = positions[i];

      final timePassed = current.timestamp - lastSaved.timestamp;

      if (timePassed >= timestampThresholdMs) {
        sampled.add(current);
        lastSaved = current;
      }
    }

    if (!_isSameTimedPosition(lastSaved, positions.last)) {
      sampled.add(positions.last);
    }

    return sampled;
  }

  bool _isSameTimedPosition(TimedPosition a, TimedPosition b) {
    return a.timestamp == b.timestamp &&
        a.position == b.position &&
        a.viewport == b.viewport;
  }

  /// Exposes sampling for focused regression tests.
  List<TimedPosition> samplePositionsForTest(
    List<TimedPosition> positions, {
    int timestampThresholdMs = 50,
  }) {
    return _samplePositions(
      positions,
      timestampThresholdMs: timestampThresholdMs,
    );
  }
}

final class _PendingTap {
  final int downTimestamp;
  final int upTimestamp;
  final int downOrder;
  final int upOrder;
  final Offset actionPosition;
  final Offset terminalPosition;
  final Rect viewport;
  final String lomRef;
  final bool isLomStateResolved;

  const _PendingTap({
    required this.downTimestamp,
    required this.upTimestamp,
    required this.downOrder,
    required this.upOrder,
    required this.actionPosition,
    required this.terminalPosition,
    required this.viewport,
    required this.lomRef,
    required this.isLomStateResolved,
  });

  int get lastEligibleTimestamp =>
      upTimestamp + doubleTapTimeout.inMilliseconds;

  int get expiryDeadline => lastEligibleTimestamp + 1;
}

final class _ActivePinchSession {
  final int startTimestamp;
  final Rect viewport;
  final String lomRef;
  final Map<int, _ActivePinchTrack> tracks;
  PinchMetricsBaseline baseline;

  _ActivePinchSession({
    required this.startTimestamp,
    required this.viewport,
    required this.lomRef,
    required this.tracks,
    required this.baseline,
  });
}

final class _ActivePinchTrack {
  final int pointerId;
  final int entryTimestamp;
  int? exitTimestamp;
  final List<TimedPosition> positions;

  _ActivePinchTrack({
    required this.pointerId,
    required this.entryTimestamp,
    required this.positions,
  });
}
