import 'package:meta/meta.dart';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

/// Internal contract for recording user events
@internal
abstract interface class SessionRecorderInternal {
  Element? get currentRouteElement;

  /// The fixed display (0, 0, width, height).
  Rect get screenViewport;
  void setScreenViewport(Rect sV);

  /// The grid on the phone's screen where the list is displayed
  /// (e.g., from Y: 100 to Y: 800).
  Rect get scrollPhysicalBounds;
  void setScrollPhysicalBounds(Rect sPB);

  /// The giant scroll with the negative top.
  Rect get scrollVirtualCanvas;
  void setScrollVirtualCanvas(Rect sVC);

  /// Determine which viewport to use based on the finger's position.
  Rect resolveViewport(Offset position);

  Root? findRoot(Offset position);

  void recordLom(LomAbstract lom);
  void recordAction(ActionEvent action);
  void recordExploration(ExplorationEvent exploration);
}
