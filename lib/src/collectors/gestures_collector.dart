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

  GestureCollector({SessionRecorderEngineInternal? engine})
      : _engine = engine ?? SessionRecorder.engine;

  /// Tracks main active pointers for gesture detection and movement history
  final Map<int, PointerTrace> _pointers = {};
  final List<PointerTrace> _lastTaps = [];
  PinchMetricsBaseline? _pinchMetrics;

  /// Called when a pointer first touches the screen.
  void onPointerDown(PointerDownEvent details) {
    final int pointer = details.pointer;

    /// Add the first [PointerTrace]
    addPointer(pointer, details.position);

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

    final PointerTrace? pointerTrace = _pointers[pointer];

    /// If for some reason the current `pointer` not exist in `_pointers`, we
    /// add it
    if (pointerTrace == null) {
      /// Add the [PointerTrace]
      addPointer(pointer, position);

      return;
    }

    pointerTrace.add(
      position,
      viewport: _engine.context.resolveViewport(position),
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
    final pointerTrace = _pointers.remove(details.pointer);

    if (pointerTrace != null) {
      _evaluatePointer(pointerTrace);
      _lastTaps.removeWhere((tap) => tap.pointer == details.pointer);
    }

    _updatePinchMetrics();
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    if (_pointers.isEmpty) {
      _pinchMetrics = null;
      _lastTaps.clear();
      return;
    }

    for (var p in _pointers.values) {
      _evaluatePointer(p);
    }

    _pointers.clear();
    _pinchMetrics = null;
    _lastTaps.clear();
  }

  /// Emit any valid gesture that is in progress to the record before
  /// the pointer is destroyed by a system interrupt.
  void _evaluatePointer(PointerTrace p) {
    if (p.type == GesturesType.pinch || p.type == GesturesType.drag) {
      _emitExplorations(p);
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
    Offset position, [
    GesturesType type = GesturesType.tap,
  ]) =>
      _pointers[pointer] = PointerTrace(pointer: pointer, type: type)
        ..add(position, viewport: _engine.context.resolveViewport(position));

  /// Update the Pinch Metrics Baseline
  void _updatePinchMetrics() {
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
    final PointerTrace? pointerTrace = _pointers.remove(pointer);

    if (pointerTrace == null) return;

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

    _lastTaps.add(pointerTrace);
    if (_lastTaps.length > 10) _lastTaps.removeAt(0);

    _emitAction(pointerTrace);
  }

  bool _evaluateDoubleTap(PointerTrace pointerTrace) {
    if (_lastTaps.isEmpty) return false;

    final currentPosition = pointerTrace.lastPosition;
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;

    _lastTaps.removeWhere(
      (tap) =>
          currentTimestamp - tap.lastTimestamp >
          doubleTapTimeout.inMilliseconds,
    );

    int? tapFoundIndex;
    for (var i = 0; i < _lastTaps.length; i++) {
      final tap = _lastTaps[i];
      final distance = (currentPosition - tap.lastPosition).distance;

      if (distance < doubleTapSlop) {
        tapFoundIndex = i;
        break;
      }
    }

    if (tapFoundIndex == null) return false;

    pointerTrace.setType(GesturesType.doubleTap);
    _emitAction(pointerTrace);
    _lastTaps.removeAt(tapFoundIndex);

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

  /// Creates and returns the `[ActionEvent]` object with its zone.
  ///
  /// - `[TapActionEvent]`
  /// - `[DoubleTapActionEvent]`
  /// - `[LongPressActionEvent]`
  ActionEvent _createActionEvent(PointerTrace pointer) {
    final TimedPosition firstPosition = pointer.first;

    final root = _engine.context.findRoot(firstPosition.position);
    int rootId = root?.id ?? 0;

    switch (pointer.type) {
      case GesturesType.longPress:
        return LongPressActionEvent(
          zone: "z$rootId",
          timestampRelative: firstPosition.timestamp,
          duration: pointer.duration,
          viewport: firstPosition.viewport,
          position: firstPosition.position,
        );
      case GesturesType.doubleTap:
        return DoubleTapActionEvent(
          zone: "z$rootId",
          timestampRelative: firstPosition.timestamp,
          viewport: firstPosition.viewport,
          position: firstPosition.position,
        );
      default:
        return TapActionEvent(
          zone: "z$rootId",
          timestampRelative: firstPosition.timestamp,
          viewport: firstPosition.viewport,
          position: firstPosition.position,
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
