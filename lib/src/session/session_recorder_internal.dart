import 'package:meta/meta.dart';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

/// Internal contract for recording user events
@internal
abstract interface class SessionRecorderInternal {
  Element? get currentRouteElement;

  void recordLom(Lom lom);
  void recordAction(ActionEvent action);
  void recordExploration(ExplorationEvent exploration);
  Root? findRoot(Offset position);
}
