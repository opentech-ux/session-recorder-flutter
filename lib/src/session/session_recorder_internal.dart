import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:session_recorder_flutter/src/models/models.dart';

/// Internal contract for spatial calculations, tree analysis, and data recording.
@internal
abstract interface class SessionRecorderInternal {
  void start();

  Element? get currentRouteElement;
  void setCurrentRouteElement(Element? element);

  void captureTree(bool comesFromNavigation);
  ValueListenable<LomAbstract?>? get notifier;
  void setCurrentlyNavigating();

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

  Chunk? extractChunk();
}

class NoOpRecorder implements SessionRecorderInternal {
  NoOpRecorder._();
  static final _instance = NoOpRecorder._();
  factory NoOpRecorder() => _instance;

  @override
  void start() {}
  @override
  Rect get screenViewport => Rect.zero;
  @override
  Rect resolveViewport(Offset p) => Rect.zero;
  @override
  Root? findRoot(Offset p) => null;
  @override
  Element? get currentRouteElement => throw UnimplementedError();
  @override
  void recordAction(ActionEvent action) {}
  @override
  void recordExploration(ExplorationEvent exploration) {}
  @override
  void recordLom(LomAbstract lom) {}
  @override
  Rect get scrollPhysicalBounds => Rect.zero;
  @override
  Rect get scrollVirtualCanvas => Rect.zero;
  @override
  void setScreenViewport(Rect sV) {}
  @override
  void setScrollPhysicalBounds(Rect sPB) {}
  @override
  void setScrollVirtualCanvas(Rect sVC) {}
  @override
  void captureTree(bool comesFromNavigation) {}
  @override
  ValueListenable<LomAbstract?>? get notifier => null;
  @override
  void setCurrentRouteElement(Element? element) {}
  @override
  Chunk? extractChunk() => null;
  @override
  void setCurrentlyNavigating() {}
}
