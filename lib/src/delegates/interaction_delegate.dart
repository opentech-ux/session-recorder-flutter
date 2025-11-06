import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'package:session_record_ux/src/constants/gestures_constants.dart';
import 'package:session_record_ux/src/services/session_record.dart';
import 'package:session_record_ux/src/delegates/helpers/action_event_helper.dart';
import 'package:session_record_ux/src/delegates/helpers/exploration_event_helper.dart';
import 'package:session_record_ux/src/delegates/chunk_delegate.dart';
import 'package:session_record_ux/src/delegates/layout_object_manager_delegate.dart';
import 'package:session_record_ux/src/utils/math_utils.dart';

import '../enums/gestures_type_enum.dart';
import '../models/models.dart' show PointerTrace, ScaleStats, TimedPosition;

/// {@template interaction_delegate}
/// A delegate responsible for managing and processing user interactions
/// across the application.
///
/// This class centralizes the detection and interpretation of gestures such as:
/// - Tap, double tap, and long press.
/// - Drag and move gestures.
/// - Scroll and pan movements.
/// - Zoom (pinch) interactions.
///
/// The [InteractionDelegate] serves as an intermediary between raw gesture
/// events and higher-level interaction logic. It interprets gesture
/// data, applies motion thresholds, and dispatches normalized events
/// to subscribed listeners or services.
///
/// Typically used internally by [SessionRecord] and then, used
/// externally by [SessionRecordWidget] to avoid calling by any other class.
///
/// {@endtemplate}
class InteractionDelegate {
  InteractionDelegate(this._navigatorKey);

  final GlobalKey<NavigatorState>? _navigatorKey;
  final ChunkDelegate _chunkDelegate = ChunkDelegate();
  final LomDelegate _lomDelegate = LomDelegate();

  /// Tracks main active pointers for gesture detection and movement history
  final Map<int, PointerTrace> _pointers = {};

  /// Stores the viewports bounds for each scrollable widget
  final Map<int, Rect> _scrollViewportRects = {};

  /// Tracks the scroll pan positions
  final Map<int, Offset> _scrollPanScrollablePositions = {};

  /// Tracks the pointers involved in a double-tap gesture
  final Map<int, PointerTrace> _doubleTapPointers = {};

  /// Tracks the pointers involved in a scale/zoom gesture
  final Map<int, PointerTrace> _scalePointers = {};

  /// Caches of the recent scroll viewport
  Rect _lastViewportScroll = Rect.zero;

  /// Initial scale metrics
  ScaleStats _initialScaleStats = ScaleStats.zero();

  /// Indicates if a scroll interaction has been detected
  bool _didScroll = false;

  /// Indicates when the user is actively performing a zoom gesture
  bool _isZooming = false;

  /// Indicates if a [Zoom] gesture has been confirmed beyonds a threshold
  bool _hasZoomed = false;

  /// Indicates if the scroll position is currently at the edge
  bool _isAtScrollEdge = false;

  // * ------------- POINTER EVENTS ------------ * //

  /// Called when a pointer first touches the screen.
  ///
  /// Adds the first [PointerTrace] object into the `_pointers` map.
  ///
  /// This marks the **start** of a potential interaction
  /// (e.g. tap, drag, or zoom detection).
  ///
  /// Doing nothing if `_didScroll` is [true].
  ///
  void onPointerDown(PointerDownEvent details) {
    final int pointer = details.pointer;
    int timestampNow = DateTime.now().millisecondsSinceEpoch;

    /// Add the first [PointerTrace]
    addPointer(pointer, details.position, timestampNow);

    final PointerTrace pointerTrace = _pointers[pointer]!;

    /// If we still don't have any pointers to evaluate in [Zoom], we initialize
    if (_pointers.length >= 2 && _initialScaleStats.scalePointers == null) {
      _initZoomValues();
    } else if (_pointers.length >= 2 &&
        _initialScaleStats.scalePointers != null) {
      /// Enter here if a [Zoom] is already being evaluated but a new
      /// pointer is added.
      _initZoomValues();
    }

    /// Initialize [LongPress] timer
    pointerTrace.timer = Timer(longPressTimeout, () {
      pointerTrace.setType(GesturesType.longPress);
      timestampNow = DateTime.now().millisecondsSinceEpoch;

      /// Clears the current [PointerTrace] to at the end compare the
      /// timestamps
      pointerTrace.clear();

      /// Subtract the `longPressTimeout` cause it's the [LongPress]'s
      /// duration by default
      pointerTrace.add(
        details.position,
        timestampNow - longPressTimeout.inMilliseconds,
      );
    });
  }

  /// Initialize, if necessary, the variables used to begin evaluating
  /// whether there is a [Zoom] or not.
  void _initZoomValues() {
    if (_pointers.length < 2) {
      _initialScaleStats = ScaleStats.zero();

      /// We set [false] if there are not active pointers
      if (_pointers.isEmpty) _hasZoomed = false;

      return;
    }

    /// Creates a [Clone] with inmutable map
    _initialScaleStats.scalePointers = {
      for (final entry in _pointers.entries)
        entry.key: PointerTrace(
          pointer: entry.value.pointer,
          positions: entry.value.positions
              .map((p) => TimedPosition(p.timestamp, p.position))
              .toList(),
          type: entry.value.type,
          timer: null, // no copiar timers
        ),
    };

    _initialScaleStats.centroid = MathUtils.getCentroid(
      _initialScaleStats.scalePointers!,
    );
    _initialScaleStats.avgDistance = MathUtils.getAverageDistance(
      _initialScaleStats.scalePointers!,
      _initialScaleStats.centroid!,
    );
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
    final int timestampNow = DateTime.now().millisecondsSinceEpoch;

    final PointerTrace? pointerTrace = _pointers[pointer];

    /// If for some reason the current `pointer` not exist in `_pointers`, we
    /// add it
    if (pointerTrace == null) {
      /// Add the [PointerTrace]
      addPointer(pointer, position, timestampNow);

      return;
    }

    final GesturesType type = pointerTrace.type;

    /// Evaluates the distance first [PointerTrace] position with the current
    /// one and if it's bigger than `touchSlop`, we start to adding the
    /// `position` and `timestampNow`
    final double distance = (position - pointerTrace.lastPosition!).distance;

    if (distance >= touchSlop) {
      /// Dispose the [Timer]
      pointerTrace.dispose();

      final lastTimedPosition = pointerTrace.last;

      if (lastTimedPosition == null ||
          (timestampNow - lastTimedPosition.timestamp) >= 100) {
        pointerTrace.add(position, timestampNow);
      }

      /// Enters here when the [Tap] or [LongPress] is moving, so it's a [Pan]
      if (type == GesturesType.tap || type == GesturesType.longPress) {
        pointerTrace.setType(GesturesType.pan);

        return;
      }

      // * ZOOM
      if (!_isZooming) {
        if (ExplorationEventHelper.evaluateZoomGesture(
          _pointers,
          _initialScaleStats,
        )) {
          _isZooming = true;
          _hasZoomed = true;

          for (var p in _pointers.values) {
            p.setType(GesturesType.zoom);
            _scalePointers.addEntries([MapEntry(p.pointer, p)]);
          }

          return;
        }

        /// Validates if `_hasZoomed` already and comes from a [Zoom]
        if (_hasZoomed && type == GesturesType.zoom) {
          pointerTrace.setType(GesturesType.pan);

          /// Removes the current `pointerTrace` to reset the positions
          _pointers.remove(pointer);
        }
      }
    }
  }

  /// Add the first [PointerTrace] with their first [TimedPosition].
  ///
  /// Set [GesturesType.tap] type by __default__.
  ///
  void addPointer(
    int pointer,
    Offset position,
    int timestampNow, [
    GesturesType type = GesturesType.tap,
  ]) =>
      _pointers[pointer] = PointerTrace(pointer: pointer, type: type)
        ..add(position, timestampNow);

  /// Called when the pointer is lifted from the screen.
  ///
  /// Finalizes the gesture logic based on previous movement analysis.
  ///
  /// If the pointer didn’t move beyond the tap threshold, a *tap* action
  /// (or *double tap*, depending on timing) may be triggered.
  ///
  /// Otherwise, other end-gesture actions like drag-end or zoom-end
  /// can be triggered.
  ///
  /// Doing nothing if `_didScroll` is [true].
  ///
  void onPointerUp(PointerUpEvent details) {
    final int pointer = details.pointer;
    final PointerTrace? pointerTrace = _pointers[pointer];

    if (pointerTrace == null) return;

    /// Remove instantly the current `pointer`
    _removePointers([pointer]);

    final GesturesType pointerType = pointerTrace.type;

    /// Timer for [LongPress] and if it's not a [LongPress] action, then dispose
    if (pointerTrace.timer != null && pointerType != GesturesType.longPress) {
      pointerTrace.dispose();
    }

    if (_isZooming) _isZooming = false;

    /// Reset [ZoomStats] value
    _initZoomValues();

    if (_chunkDelegate.hasChunk) {
      switch (pointerType) {
        case GesturesType.longPress:
          final int timestampNow = DateTime.now().millisecondsSinceEpoch;

          pointerTrace.add(details.position, timestampNow);

          final actionList = ActionEventHelper.detectActionEvent(
            _navigatorKey?.currentContext,
            pointerTrace,
            _lastViewportScroll,
            _lomDelegate.rootReference,
          );

          if (actionList.isNotEmpty) {
            for (final action in actionList) {
              _chunkDelegate.addActionEvent(action);
            }
          }

          return;
        case GesturesType.zoom:
          if (_scalePointers.length >= 2) {
            final touchExplorationEvents =
                ExplorationEventHelper.detectTouchExplorationEvent(
                  _scalePointers.values.toList(),
                  _lastViewportScroll,
                );

            if (_chunkDelegate.hasChunk) {
              _chunkDelegate.addExplorationEvents(touchExplorationEvents);
            }
          }

          _scalePointers.clear();

          break;
        case GesturesType.pan:
          final lastTimedPosition = pointerTrace.last;

          final Offset position = details.position;

          if (lastTimedPosition == null ||
              lastTimedPosition.position != position) {
            final int tsNow = DateTime.now().millisecondsSinceEpoch;
            pointerTrace.add(position, tsNow);
          }

          /// If `_didScroll` is [true], the [ExplorationEvent] logic does into
          /// the [ScrollNotification]
          if (_didScroll) return;

          final touchExplorationEvents =
              ExplorationEventHelper.detectTouchExplorationEvent([
                pointerTrace,
              ], _lastViewportScroll);

          if (_chunkDelegate.hasChunk) {
            _chunkDelegate.addExplorationEvents(touchExplorationEvents);
          }

          return;
        case GesturesType.tap:
        case GesturesType.doubleTap:
          _doubleTapPointers[pointer] = pointerTrace;

          pointerTrace.timer = Timer(doubleTapTimeout, () {
            pointerTrace.setType(GesturesType.tap);

            final actionList = ActionEventHelper.detectActionEvent(
              _navigatorKey?.currentContext,
              pointerTrace,
              _lastViewportScroll,
              _lomDelegate.rootReference,
            );

            if (actionList.isNotEmpty) {
              for (final action in actionList) {
                _chunkDelegate.addActionEvent(action);
              }
            }

            _doubleTapPointers.clear();

            return;
          });

          final PointerTrace? lastPointer = _doubleTapPointers[pointer - 1];

          /// If the last pointer is not [null], we can assume in advance that
          /// there may be some double tapping.
          if (lastPointer != null && lastPointer.type == GesturesType.tap) {
            final int lastDifference =
                pointerTrace.lastTimestamp! - lastPointer.lastTimestamp!;
            final double lastDistance =
                (pointerTrace.lastPosition! - lastPointer.lastPosition!)
                    .distance;

            if (lastDifference < doubleTapTimeout.inMilliseconds &&
                lastDistance < doubleTapTouchSlop) {
              /// Dispose both [Timer]s
              lastPointer.dispose();
              pointerTrace.dispose();

              /// Set both [DoubleTap] action
              pointerTrace.setType(GesturesType.doubleTap);
              lastPointer.setType(GesturesType.doubleTap);

              final actionList = ActionEventHelper.detectActionEvent(
                _navigatorKey?.currentContext,
                pointerTrace,
                _lastViewportScroll,
                _lomDelegate.rootReference,
              );

              if (actionList.isNotEmpty) {
                for (final action in actionList) {
                  _chunkDelegate.addActionEvent(action);
                }
              }

              _doubleTapPointers.clear();
            }
          }

          break;

        default:
      }
    }
  }

  /// Called when the pointer interaction is unexpectedly canceled.
  ///
  /// This may happen when the system interrupts the gesture (e.g. another
  /// widget takes control of the pointer, or the app loses focus).
  ///
  /// Any ongoing gesture state should be reset here.
  void onPointerCancel() {
    _didScroll = false;
    if (_isZooming) _isZooming = false;

    _initZoomValues();

    _scalePointers.clear();
    _doubleTapPointers.clear();
    _pointers.clear();
  }

  /// Removes the specified pointers from the active map.
  ///
  /// Ensures that only the pointer corresponding to the released
  /// touch event is cleared, without affecting other active pointers
  /// still interacting with the screen.
  void _removePointers(List<int> pointers) =>
      _pointers.removeWhere((key, value) => (pointers.any((p) => p == key)));

  /// Handles incoming [ScrollNotification] events to detect and record scroll
  /// interactions.
  ///
  /// This method manages viewports and relevant finger scroll positions to
  /// then converts them into [ScrollExplorationEvent] and [PanExplorationEvent].
  bool handleScrollNotification(ScrollNotification notification) {
    final context = notification.context;

    if (context == null) return false;

    final scrollableState = Scrollable.maybeOf(context);

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle) {
        _didScroll = false;
        _isAtScrollEdge = false;

        final scrollExplorationEvents =
            ExplorationEventHelper.getScrollExploration(
              _scrollPanScrollablePositions,
              _scrollViewportRects,
            );

        if (_chunkDelegate.hasChunk) {
          _chunkDelegate.addExplorationEvents(scrollExplorationEvents);
        }
      } else {
        _didScroll = true;
      }
    } else {
      ScrollPosition scrollPosition;

      if (scrollableState != null) {
        scrollPosition = scrollableState.position;
      } else {
        scrollPosition = notification.metrics as ScrollPosition;
      }

      final ts = DateTime.now().millisecondsSinceEpoch;

      final lastRect = _scrollViewportRects.entries.isNotEmpty
          ? _scrollViewportRects.entries.last
          : null;

      if (notification is! OverscrollNotification) {
        if (!_isAtScrollEdge) {
          captureViewportGeometry(context, scrollPosition);

          if (lastRect == null || scrollPosition.atEdge) {
            _scrollViewportRects[ts] = _lastViewportScroll;
          } else {
            if (lastRect.value != _lastViewportScroll) {
              _scrollViewportRects[ts] = _lastViewportScroll;
            }
          }
        }

        /// First set the `rect` before to know it is in the edge
        _isAtScrollEdge = scrollPosition.atEdge;

        if (notification is ScrollStartNotification) {
          if (notification.dragDetails != null) {
            _scrollPanScrollablePositions[ts] =
                notification.dragDetails!.globalPosition;
          }
        } else if (notification is ScrollUpdateNotification) {
          if (notification.dragDetails != null) {
            _scrollPanScrollablePositions[ts] =
                notification.dragDetails!.globalPosition;
          }
        } else if (notification is ScrollEndNotification) {
          if (notification.dragDetails != null) {
            _scrollPanScrollablePositions[ts] =
                notification.dragDetails!.globalPosition;
          }
        }
      }
    }

    return false;
  }

  /// Computes and updates the current viewport rectangle for a scrollable
  /// position.
  ///
  /// The method retrieves the associated [RenderBox] from the given `context`
  /// and converts its local bounds into global screen coordinates. That
  /// rectangle is used as the initial viewport.
  ///
  /// If a [ScrollPosition] is provided, the viewport is expanded to represent
  /// the entire scrollable content (not just the visible portion).
  ///
  /// If no valid [RenderBox] can be resolved or [scrollPosition] is null,
  /// the method falls back to storing only the visible viewport bounds.
  void captureViewportGeometry(
    BuildContext context,
    ScrollPosition? scrollPosition,
  ) {
    final renderObject = context.findRenderObject();

    if (renderObject is! RenderBox) return;

    final initPosition = renderObject.localToGlobal(Offset.zero);

    Rect rect = initPosition & renderObject.size;

    _lastViewportScroll = rect;

    if (scrollPosition == null) return;

    final double contentHeight =
        scrollPosition.maxScrollExtent + scrollPosition.viewportDimension;
    final double left = rect.left;
    final double contentTop = rect.top - scrollPosition.pixels;

    rect = Rect.fromLTWH(left, contentTop, rect.width, contentHeight);

    _lastViewportScroll = rect;
  }
}
