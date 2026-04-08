import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_engine.dart';
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
      viewport: _engine.recorder.resolveViewport(position),
    );

    if (pointerTrace.type != GesturesType.pinch &&
        pointerTrace.distance >= touchSlop) {
      pointerTrace.setType(GesturesType.drag);
    }

    bool isScaling = false;

    if (_pointers.length >= 2 && _pinchMetrics != null) {
      isScaling = MathUtils.evaluatePinchGesture(_pointers, _pinchMetrics!);
    }

    final bool isAlreadyScaling = pointerTrace.type == GesturesType.pinch;

    if (isScaling || isAlreadyScaling) {
      /// Split and emit the exploration
      for (var p in _pointers.values) {
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
    }

    _updatePinchMetrics();
  }

  /// Forced shutdown when the collection is interrupted
  void forceRecordCollector() {
    if (_pointers.isEmpty) return;

    for (var p in _pointers.values) {
      _evaluatePointer(p);
    }

    _pointers.clear();
    _pinchMetrics = null;
  }

  /// Emit any valid gesture that is in progress to the [Record] before
  /// the pointer is destroyed by a system interrupt.
  void _evaluatePointer(PointerTrace p) {
    if (p.type == GesturesType.pinch || p.type == GesturesType.drag) {
      _emitExplorations(p);
    } else if (p.distance >= touchSlop) {
      p.setType(GesturesType.drag);
      _emitExplorations(p);
    }
  }

  /// Add the first [PointerTrace] with their first [TimedPosition].
  ///
  /// Set [GesturesType.tap] type by __default__.
  void addPointer(
    int pointer,
    Offset position, [
    GesturesType type = GesturesType.tap,
  ]) =>
      _pointers[pointer] = PointerTrace(pointer: pointer, type: type)
        ..add(position, viewport: _engine.recorder.resolveViewport(position));

  /// Re-set the [Pinch]'s stats
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
      // pointerTrace.setType(GesturesType.pinch);
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

      return;
    }

    _updatePinchMetrics();

    // * LONG PRESS
    if (pointerTrace.duration >= longPressTimeout &&
        pointerTrace.distance < touchSlop) {
      pointerTrace.setType(GesturesType.longPress);
      final action = _createActionEvent(pointerTrace);
      _engine.recorder.recordAction(action);
      return;
    }

    // * DRAG
    if (pointerTrace.distance >= touchSlop) {
      pointerTrace.setType(GesturesType.drag);
      final explorations = _createExplorationEvent(pointerTrace);
      for (ExplorationEvent exploration in explorations) {
        _engine.recorder.recordExploration(exploration);
      }
      return;
    }

    // * DOUBLE TAP
    final currentPosition = pointerTrace.lastPosition;
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    _lastTaps.removeWhere(
      (pointer) =>
          (currentTimestamp - pointer.lastTimestamp) >
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

    if (tapFoundIndex != null) {
      pointerTrace.setType(GesturesType.doubleTap);
      final action = _createActionEvent(pointerTrace);
      _engine.recorder.recordAction(action);
      _lastTaps.removeAt(tapFoundIndex);
      return;
    }

    if (pointerTrace.isOrphanedPointer &&
        pointerTrace.duration.inMilliseconds < 250) {
      return;
    }

    // * TAP
    pointerTrace.setType(GesturesType.tap);
    _lastTaps.add(pointerTrace);

    final action = _createActionEvent(pointerTrace);
    _engine.recorder.recordAction(action);
  }

  void _emitExplorations(PointerTrace pointerTrace) {
    final explorations = _createExplorationEvent(pointerTrace);
    if (explorations.isNotEmpty) {
      for (final exploration in explorations) {
        _engine.recorder.recordExploration(exploration);
      }
    }
  }

  /// Creates and returns the `[ActionEvent]` object with its zone.
  ///
  /// - `[TapActionEvent]`
  /// - `[DoubleTapActionEvent]`
  /// - `[LongPressActionEvent]`
  ActionEvent _createActionEvent(PointerTrace pointer) {
    final TimedPosition firstPosition = pointer.first;

    final root = _engine.recorder.findRoot(firstPosition.position);
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
        explorationEvents = _getDragExploration(pointer.positions);
        break;
      case GesturesType.pinch:
        explorationEvents = [_getPinchExploration(pointer)];

        break;

      default:
    }

    return explorationEvents;
  }

  /// Converts the recorded `[PointerTrace]` data into a list of `[DragExplorationEvent]`
  /// instances.
  List<DragExplorationEvent> _getDragExploration(
    List<TimedPosition> positions,
  ) {
    if (positions.isEmpty) return [];

    final sampledPositions = _samplePositions(positions);

    List<DragExplorationEvent> panList = List.from(
      sampledPositions.map(
        (touchDrag) => DragExplorationEvent(
          timestamp: touchDrag.timestamp,
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
      endTimestamp: pointer.lastTimestamp,
      viewport: pointer.first.viewport,
      positions: sampledPositions.map((p) => p.position).toList(),
    );

    return pinch;
  }

  /// Returns a sampled version of `positions` keeping every `nth` point.
  /// Always includes the first and last position to preserve start and end.
  List<TimedPosition> _samplePositions(
    List<TimedPosition> positions, {
    int nth = 8,
  }) {
    if (positions.length <= 2) return positions;
    final sampled = <TimedPosition>[];
    for (var i = 0; i < positions.length; i++) {
      if (i == 0 || i == positions.length - 1 || i % nth == 0) {
        sampled.add(positions[i]);
      }
    }
    return sampled;
  }
}
