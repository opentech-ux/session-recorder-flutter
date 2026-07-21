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
  final List<PointerTrace> _lastTaps = [];
  PinchMetricsBaseline? _pinchMetrics;

  /// Called when a pointer first touches the screen.
  void onPointerDown(PointerDownEvent details) {
    final int pointer = details.pointer;
    final viewport = _viewportProvider();
    if (viewport == null) {
      _ignoredPointers.add(pointer);
      return;
    }

    final inheritedLomRef = _oldestActivePointer()?.lomRef;
    final lomRef = _engine.context.resolveLomRefForPointerDown(
      inheritedLomRef: inheritedLomRef,
    );

    /// Add the first [PointerTrace]
    addPointer(
      pointer,
      details.position,
      viewport: viewport,
      lomRef: lomRef,
    );

    if (_ignoredPointers.contains(pointer)) return;

    _updatePinchMetrics();
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
      addPointer(pointer, position);

      return;
    }

    if (pointerTrace.isEmpty) {
      _updatePinchMetrics();
      return;
    }

    final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
    pointerTrace.add(
      position,
      viewport: viewport,
    );

    if (pointerTrace.type != GesturesType.pinch &&
        pointerTrace.distance >= touchSlop) {
      // * SPLIT LONG PRESS
      final bool isAlreadyLongPress =
          pointerTrace.type == GesturesType.longPress;

      if (isAlreadyLongPress) {
        _emitAction(pointerTrace);

        _pointers[pointerTrace.pointer] = pointerTrace.splitForTransition(
          newType: GesturesType.drag,
        );
      } else {
        pointerTrace.setType(GesturesType.drag);
      }
    } else if (pointerTrace.type != GesturesType.pinch &&
        pointerTrace.distance <= touchSlop &&
        pointerTrace.duration >= longPressTimeout) {
      pointerTrace.setType(GesturesType.longPress);
    }

    bool isScaling = false;

    if (_pointers.length >= 2 && _pinchMetrics != null) {
      isScaling = MathUtils.evaluatePinchGesture(_pointers, _pinchMetrics!);
    }

    final bool isAlreadyScaling = pointerTrace.type == GesturesType.pinch;

    // * SPLIT SCALING
    if (isScaling || isAlreadyScaling) {
      /// Split and emit the exploration
      for (var p in _pointers.values) {
        final isSomePointerPinching =
            _pinchMetrics!.initialPositions!.containsKey(p.pointer);

        if (!isSomePointerPinching) continue;

        if (p.type == GesturesType.pinch) continue;

        if (p.type == GesturesType.drag) {
          _emitExplorations(p);

          _pointers[p.pointer] = p.splitForTransition(
            newType: GesturesType.pinch,
          );
        } else {
          p.setType(GesturesType.pinch);
        }
      }
    }
  }

  /// Called whenever the pointer cancels in the screen (e.g. a phone call).
  void onPointerCancel(PointerCancelEvent details) {
    final pointer = details.pointer;
    _ignoredPointers.remove(pointer);
    final pointerTrace = _pointers.remove(pointer);
    _lastTaps.removeWhere((tap) => tap.pointer == pointer);

    if (pointerTrace != null) {
      if (!pointerTrace.isEmpty &&
          (pointerTrace.type == GesturesType.drag ||
              pointerTrace.type == GesturesType.pinch)) {
        _emitExplorations(pointerTrace);
      }

      if (pointerTrace.type == GesturesType.pinch) {
        _preserveRemainingPinchPointer();
      }
    }

    _updatePinchMetrics();
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    if (_pointers.isEmpty) {
      _pinchMetrics = null;
      _lastTaps.clear();
      _ignoredPointers.clear();
      return;
    }

    for (var p in _pointers.values) {
      if (p.isEmpty) continue;
      _evaluatePointer(p);
    }

    _pointers.clear();
    _pinchMetrics = null;
    _lastTaps.clear();
    _ignoredPointers.clear();
  }

  /// Emit any valid gesture that is in progress to the record before
  /// the pointer is destroyed by a system interrupt.
  void _evaluatePointer(PointerTrace p) {
    if (p.type == GesturesType.pinch || p.type == GesturesType.drag) {
      _emitExplorations(p);
    } else if (p.type == GesturesType.longPress ||
        (p.duration >= longPressTimeout && p.distance < touchSlop)) {
      _evaluateLongPress(p);
    } else if (p.distance >= touchSlop) {
      p.setType(GesturesType.drag);
      _emitExplorations(p);
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
  }) {
    final resolvedViewport = viewport ?? _viewportProvider();
    if (resolvedViewport == null) {
      _ignoredPointers.add(pointer);
      return;
    }

    _ignoredPointers.remove(pointer);
    final resolvedLomRef =
        lomRef ??
        _oldestActivePointer()?.lomRef ??
        _engine.context.currentLomRef ??
        '';

    _pointers[pointer] = PointerTrace(
      pointer: pointer,
      lomRef: resolvedLomRef,
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

  /// Update the Pinch Metrics Baseline
  void _updatePinchMetrics() {
    var removedPinchPointer = false;
    final emptyPointers = _pointers.entries
        .where((entry) => entry.value.isEmpty)
        .toList();

    for (final entry in emptyPointers) {
      _pointers.remove(entry.key);
      _ignoredPointers.add(entry.key);
      if (entry.value.type == GesturesType.pinch) {
        removedPinchPointer = true;
      }
    }

    if (removedPinchPointer) _preserveRemainingPinchPointer();

    if (_pointers.length >= 2) {
      _pinchMetrics = PinchMetricsBaseline(
        initialPositions: _pointers.map(
          (key, pointer) => MapEntry(key, pointer.lastPosition),
        ),
        centroid: MathUtils.getCentroid(_pointers),
        avgDistance: MathUtils.getAverageDistance(_pointers),
      );
    } else {
      _pinchMetrics = null;
    }
  }

  /// Called when the pointer is lifted from the screen.
  ///
  /// Finalizes the gesture logic based on previous movement analysis.
  void onPointerUp(PointerUpEvent details) {
    final int pointer = details.pointer;
    _ignoredPointers.remove(pointer);
    final PointerTrace? pointerTrace = _pointers.remove(pointer);

    if (pointerTrace == null) return;

    if (pointerTrace.isEmpty) {
      if (pointerTrace.type == GesturesType.pinch) {
        _preserveRemainingPinchPointer();
      }
      _updatePinchMetrics();
      return;
    }

    final viewport = _viewportProvider() ?? pointerTrace.last.viewport;
    pointerTrace.add(
      details.position,
      viewport: viewport,
    );

    // * PINCH
    if (pointerTrace.type == GesturesType.pinch) {
      _evaluatePinch(pointerTrace);

      return;
    }

    _updatePinchMetrics();

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

    // * ORPHANED POINTER
    if (pointerTrace.isOrphanedPointer &&
        DateTime.now().millisecondsSinceEpoch - pointerTrace.firstTimestamp <
            250) {
      return;
    }

    // * TAP
    pointerTrace.setType(GesturesType.tap);

    // * DOUBLE TAP
    if (_evaluateDoubleTap(pointerTrace)) return;

    if (!pointerTrace.isEmpty) {
      _lastTaps.add(pointerTrace);
      if (_lastTaps.length > 10) _lastTaps.removeAt(0);
    }

    _emitAction(pointerTrace);
  }

  bool _evaluateDoubleTap(PointerTrace pointerTrace) {
    _lastTaps.removeWhere((tap) => tap.isEmpty);
    if (_lastTaps.isEmpty) return false;

    final currentPosition = pointerTrace.lastPosition;
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;

    _lastTaps.removeWhere(
      (tap) =>
          currentTimestamp - tap.lastTimestamp >
          doubleTapTimeout.inMilliseconds,
    );

    int? tapFoundIndex;
    double? bestDistance;
    for (var i = 0; i < _lastTaps.length; i++) {
      final tap = _lastTaps[i];
      final elapsed = currentTimestamp - tap.lastTimestamp;
      if (elapsed > doubleTapTimeout.inMilliseconds) continue;

      final distance = (currentPosition - tap.lastPosition).distance;

      if (distance < doubleTapSlop &&
          (bestDistance == null || distance < bestDistance)) {
        bestDistance = distance;
        tapFoundIndex = i;
      }
    }

    if (tapFoundIndex == null) return false;

    final originTap = _lastTaps.removeAt(tapFoundIndex);
    pointerTrace.setType(GesturesType.doubleTap);
    _emitAction(
      pointerTrace,
      doubleTapOriginTimestampRelative: originTap.firstTimestamp,
      doubleTapOriginPosition: originTap.firstPosition,
    );

    return true;
  }

  void _evaluateDrag(PointerTrace pointerTrace) {
    pointerTrace.setType(GesturesType.drag);
    final explorations = _createExplorationEvent(pointerTrace);
    for (ExplorationEvent exploration in explorations) {
      _engine.context.recordExploration(exploration);
    }
  }

  void _evaluateLongPress(PointerTrace pointerTrace) {
    pointerTrace.setType(GesturesType.longPress);
    final action = _createActionEvent(pointerTrace);
    _engine.context.recordAction(action);
  }

  void _evaluatePinch(PointerTrace pointerTrace) {
    _emitExplorations(pointerTrace);

    if (_pointers.length == 1) {
      final lastPointer = _pointers.values.first;

      if (lastPointer.type == GesturesType.pinch) {
        _emitExplorations(lastPointer);

        _pointers[lastPointer.pointer] = lastPointer.splitForTransition(
          newType: GesturesType.tap,
          isOrphanedPointer: true,
        );
      }
    }

    _updatePinchMetrics();
  }

  void _preserveRemainingPinchPointer() {
    final remainingPinchPointers = _pointers.values
        .where(
          (trace) => trace.type == GesturesType.pinch && !trace.isEmpty,
        )
        .toList();

    if (remainingPinchPointers.length != 1) return;

    final remainingPointer = remainingPinchPointers.single;
    _emitExplorations(remainingPointer);
    _pointers[remainingPointer.pointer] = remainingPointer.splitForTransition(
      newType: GesturesType.tap,
      isOrphanedPointer: true,
    );
  }

  void _emitExplorations(PointerTrace pointerTrace) {
    final explorations = _createExplorationEvent(pointerTrace);
    if (explorations.isNotEmpty) {
      for (final exploration in explorations) {
        _engine.context.recordExploration(exploration);
      }
    }
  }

  void _emitAction(
    PointerTrace pointerTrace, {
    int? doubleTapOriginTimestampRelative,
    Offset? doubleTapOriginPosition,
  }) {
    final action = _createActionEvent(
      pointerTrace,
      doubleTapOriginTimestampRelative: doubleTapOriginTimestampRelative,
      doubleTapOriginPosition: doubleTapOriginPosition,
    );
    _engine.context.recordAction(action);
  }

  /// Creates and returns the `[ActionEvent]` object with its LOM ref.
  ///
  /// - `[TapActionEvent]`
  /// - `[DoubleTapActionEvent]`
  /// - `[LongPressActionEvent]`
  ActionEvent _createActionEvent(
    PointerTrace pointer, {
    int? doubleTapOriginTimestampRelative,
    Offset? doubleTapOriginPosition,
  }) {
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
      case GesturesType.doubleTap:
        return DoubleTapActionEvent(
          timestampRelative: firstPosition.timestamp,
          viewport: firstPosition.viewport,
          position: firstPosition.position,
          lomRef: firstPosition.lomRef,
          originTimestampRelative: doubleTapOriginTimestampRelative,
          originPosition: doubleTapOriginPosition,
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

  /// Creates a `[ExplorationEvent]` gonna create it by the `pointers` type
  ///
  /// Could return a `[DragExplorationEvent]`, `[PinchExplorationEvent]` list
  List<ExplorationEvent> _createExplorationEvent(PointerTrace pointer) {
    List<ExplorationEvent> explorationEvents = [];

    switch (pointer.type) {
      case GesturesType.drag:
        explorationEvents = _getDragExploration(pointer);
        break;
      case GesturesType.pinch:
        explorationEvents = [_getPinchExploration(pointer)];

        break;

      default:
        return [];
    }

    return explorationEvents;
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

  /// Converts the recorded `[PointerTrace]` data into a list of `[PinchExplorationEvent]`
  /// instances.
  PinchExplorationEvent _getPinchExploration(PointerTrace pointer) {
    final sampledPositions = _samplePositions(pointer.positions);

    final pinch = PinchExplorationEvent(
      timestamp: pointer.firstTimestamp,
      pointer: pointer.pointer,
      endTimestamp: pointer.lastTimestamp,
      viewport: pointer.first.viewport,
      positions: sampledPositions.map((p) => p.position).toList(),
      lomRef: pointer.first.lomRef,
    );

    return pinch;
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
