import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../enums/gestures_type_enum.dart';
import '../../models/models.dart'
    show
        ActionEvent,
        PointerTrace,
        Root,
        TimedPosition,
        LongPressActionEvent,
        DoubleTapActionEvent,
        TapActionEvent;

class ActionEventHelper {
  /// Detects and creates different [ActionEvent] types like:
  ///
  /// - [TapActionEvent]
  /// - [DoubleTapActionEvent]
  /// - [LongPressActionEvent]
  static List<ActionEvent> detectActionEvent(
    BuildContext? context,
    PointerTrace pointer,
    Rect viewportScroll,
    Map<int, Root> rootReference,
  ) {
    try {
      if (context == null) return [];

      final List<ActionEvent> actionEvents = [];

      final ActionEvent? actionEvent = _createActionEvent(
        context,
        pointer,
        viewportScroll,
        rootReference,
      );

      if (actionEvent == null) return [];

      actionEvents.add(actionEvent);

      return actionEvents;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return [];
    }
  }

  /// Creates and returns the [ActionEvent] object with its zone.
  static ActionEvent? _createActionEvent(
    BuildContext context,
    PointerTrace pointer,
    Rect viewportScroll,
    Map<int, Root> rootReference,
  ) {
    try {
      final TimedPosition firstPosition = pointer.first ?? pointer.last!;

      final root = _findZone(context, firstPosition, rootReference);

      if (root == null) return null;

      switch (pointer.type) {
        case GesturesType.longPress:
          return LongPressActionEvent(
            zone: "z${root.id}",
            timestampRelative: firstPosition.timestamp,
            duration: pointer.duration,
            viewport: viewportScroll,
            position: firstPosition.position,
          );
        case GesturesType.doubleTap:
          return DoubleTapActionEvent(
            zone: "z${root.id}",
            timestampRelative: firstPosition.timestamp,
            viewport: viewportScroll,
            position: firstPosition.position,
          );
        default:
          return TapActionEvent(
            zone: "z${root.id}",
            timestampRelative: firstPosition.timestamp,
            viewport: viewportScroll,
            position: firstPosition.position,
          );
      }
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return null;
    }
  }

  /// Finds the [Zone] where the user has tapped.
  ///
  /// Get the [RenderBox] hit test with the `firstPosition` position.
  static Root? _findZone(
    BuildContext context,
    TimedPosition firstPosition,
    Map<int, Root> rootReference,
  ) {
    try {
      if (!context.mounted) return null;

      final RenderObject? rootRender = context.findRenderObject();

      if (rootRender == null || rootRender is! RenderBox) return null;

      final RenderBox rootBox = rootRender;

      final BoxHitTestResult boxHitTestResult = BoxHitTestResult();

      rootBox.hitTest(
        boxHitTestResult,
        position: rootBox.globalToLocal(firstPosition.position),
      );

      Root? rootTouched;

      final entries = boxHitTestResult.path.toList();

      // TODO : To RE-VALIDATE the current Zone, we can do a logic to compare the hit size and get all Roots with this size (have to do logic scroll in Listener)

      for (int i = 0; i <= entries.length - 1; i++) {
        final target = entries[i].target;

        if (target is! RenderBox) continue;

        if (!target.hasSize || target.size == Size.zero) continue;

        final renderBox = target;

        final renderExists = rootReference.containsKey(renderBox.hashCode);

        if (!renderExists) continue;

        rootTouched = rootReference[target.hashCode]!;

        break;
      }

      if (rootTouched == null) return null;

      return rootTouched;
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return null;
    }
  }
}
