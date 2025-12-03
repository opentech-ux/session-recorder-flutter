import 'package:flutter/rendering.dart';

import 'package:session_recorder_flutter/src/utils/session_logger.dart';

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
  /// Detects and creates different `[ActionEvent]` types like:
  ///
  /// - `[TapActionEvent]`
  /// - `[DoubleTapActionEvent]`
  /// - `[LongPressActionEvent]`
  static List<ActionEvent> detectActionEvent(
    PointerTrace pointer,
    Rect viewportScroll,
    Map<int, Root> rootReference,
  ) {
    try {
      final List<ActionEvent> actionEvents = [];

      final ActionEvent actionEvent = _createActionEvent(
        pointer,
        viewportScroll,
        rootReference,
      );

      actionEvents.add(actionEvent);

      return actionEvents;
    } catch (e, s) {
      SessionLogger.elog("!! >> [Some error]", e, s);
      return [];
    }
  }

  /// Creates and returns the `[ActionEvent]` object with its zone.
  static ActionEvent _createActionEvent(
    PointerTrace pointer,
    Rect viewportScroll,
    Map<int, Root> rootReference,
  ) {
    try {
      final TimedPosition firstPosition = pointer.first ?? pointer.last!;

      final root = _findZone(firstPosition, rootReference);

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
      SessionLogger.elog("!! >> [Some error]", e, s);
      final root = rootReference.values.first;
      return TapActionEvent(
        zone: "z${root.id}",
        timestampRelative: pointer.firstTimestamp ?? pointer.lastTimestamp!,
        viewport: viewportScroll,
        position: pointer.firstPosition ?? pointer.lastPosition!,
      );
    }
  }

  /// Finds the `[Zone]` where the user has tapped.
  ///
  /// Get the `[RenderBox]` hit test with the `firstPosition` position.
  static Root _findZone(
    TimedPosition firstPosition,
    Map<int, Root> rootReference,
  ) {
    try {
      final HitTestResult boxHitTestResult = HitTestResult();

      final RenderView rootView = RendererBinding.instance.renderViews.first;

      RendererBinding.instance.hitTestInView(
        boxHitTestResult,
        firstPosition.position,
        rootView.flutterView.viewId,
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

        rootTouched = rootReference[renderBox.hashCode]!;

        break;
      }

      if (rootTouched == null) return rootReference.values.first;

      return rootTouched;
    } catch (e, s) {
      SessionLogger.elog("!! >> [Some error]", e, s);
      return rootReference.values.first;
    }
  }
}
