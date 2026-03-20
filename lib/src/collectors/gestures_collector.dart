import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';
import 'package:session_recorder_flutter/src/utils/math_utils.dart';

/// Detects and records tap, double-tap, long-press, drag, and pinch gestures.
class GestureCollector {
  final SessionRecorderInternal _recorder;

  GestureCollector(this._recorder);

  /// Tracks main active pointers for gesture detection and movement history
  final Map<int, PointerTrace> _pointers = {};

  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  double? _pinchInitialAverage;

  /// Most recent computed scale — updated every move while pinch is active.
  /// Stored here so every finger can read the same value when lifting.
  // double _pinchLatestScale = 1.0;
  // Offset _pinchLatestCenter = Offset.zero;
  // int _pinchFingerCount = 0;

  /// Called when a pointer first touches the screen.
  void onPointerDown(PointerDownEvent details) {
    final int pointer = details.pointer;

    /// Add the first [PointerTrace]
    addPointer(pointer, details.position);

    if (_pointers.length >= 2) {
      _pinchInitialAverage = MathUtils.getAverageDistance(_pointers);
    }
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
      viewport: _recorder.viewport.contains(position)
          ? _recorder.viewport
          : Rect.zero,
    );

    if (_pointers.length < 2 || _pinchInitialAverage == null) return;

    final avg = MathUtils.getAverageDistance(_pointers);
    final avgAbsolute = (avg - _pinchInitialAverage!).abs();

    if (avgAbsolute >= pinchSlop) {
      for (var p in _pointers.values) {
        p.setType(GesturesType.pinch);
      }
    }

    // // Keep pinch metrics up to date so every finger reads the latest values.
    // _pinchLatestScale = _pinchInitialAverage! > 0
    //     ? avg / _pinchInitialAverage!
    //     : 1.0;
    // _pinchLatestCenter = _centerOf(
    //   _pointers.values.map((pointer) => pointer.lastPosition).toList(),
    // );
    // _pinchFingerCount = _pointers.length;
  }

  /// Add the first [PointerTrace] with their first [TimedPosition].
  ///
  /// Set [GesturesType.tap] type by __default__.
  void addPointer(
    int pointer,
    Offset position, [
    GesturesType type = GesturesType.tap,
  ]) => _pointers[pointer] = PointerTrace(pointer: pointer, type: type)
    ..add(
      position,
      viewport: _recorder.viewport.contains(position)
          ? _recorder.viewport
          : Rect.zero,
    );

  /// Called when the pointer is lifted from the screen.
  ///
  /// Finalizes the gesture logic based on previous movement analysis.
  void onPointerUp(PointerUpEvent details) {
    final int pointer = details.pointer;
    final PointerTrace? pointerTrace = _pointers.remove(pointer);

    if (pointerTrace == null) return;

    // final pinchScale = _pinchLatestScale;
    // final pinchCenter = _pinchLatestCenter;
    // final pinchFingers = _pinchFingerCount;

    // if (_pointers.isEmpty) {
    //   _pinchInitialAverage = null;
    //   _pinchLatestScale = 1.0;
    //   _pinchLatestCenter = Offset.zero;
    //   _pinchFingerCount = 0;
    // }

    // * pinch
    if (pointerTrace.type == GesturesType.pinch) {
      pointerTrace.setType(GesturesType.pinch);
      final explorations = _createExplorationEvent(pointerTrace);
      _recorder.recordExploration(explorations.first);
      return;
    }

    // * DRAG
    if (pointerTrace.distance >= touchSlop) {
      pointerTrace.setType(GesturesType.drag);
      final explorations = _createExplorationEvent(pointerTrace);
      for (ExplorationEvent exploration in explorations) {
        _recorder.recordExploration(exploration);
      }
      return;
    }

    // * LONG PRESS
    if (pointerTrace.duration >= longPressTimeout) {
      pointerTrace.setType(GesturesType.longPress);
      final action = _createActionEvent(pointerTrace);
      _recorder.recordAction(action);
      _lastTapTime = null;
      _lastTapPosition = null;
      return;
    }

    // * DOUBLE TAP
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds <
            doubleTapTimeout.inMilliseconds &&
        _lastTapPosition != null &&
        (pointerTrace.lastPosition - _lastTapPosition!).distance < 40) {
      pointerTrace.setType(GesturesType.doubleTap);
      final action = _createActionEvent(pointerTrace);
      _recorder.recordAction(action);
      _lastTapPosition = null;
      _lastTapTime = null;
      return;
    }

    // * TAP
    pointerTrace.setType(GesturesType.tap);
    final action = _createActionEvent(pointerTrace);
    _recorder.recordAction(action);

    _lastTapPosition = pointerTrace.lastPosition;
    _lastTapTime = now;
  }

  /// Creates and returns the `[ActionEvent]` object with its zone.
  ///
  /// - `[TapActionEvent]`
  /// - `[DoubleTapActionEvent]`
  /// - `[LongPressActionEvent]`
  ActionEvent _createActionEvent(PointerTrace pointer) {
    final TimedPosition firstPosition = pointer.first;

    final root = _recorder.findRoot(firstPosition.position);
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
      viewport: _recorder.viewport,
      positions: sampledPositions.map((p) => p.position).toList(),
    );

    return pinch;
  }

  /// Returns a sampled version of `positions` keeping every `nth` point.
  /// Always includes the first and last position to preserve start and end.
  List<TimedPosition> _samplePositions(
    List<TimedPosition> positions, {
    int nth = 6,
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
