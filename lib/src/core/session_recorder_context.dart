import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';

import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';

/// Internal contract for session state, tree analysis, and data recording.
@internal
abstract interface class SessionRecorderContext {
  void start();
  void dispose();

  void captureTree(bool comesFromNavigation, {bool bypassCooldown = false});
  ValueListenable<LomAbstract?>? get notifier;
  void setCurrentlyNavigating();
  void setScrollActive(bool isActive);
  void markPostScrollCapturePending();
  void capturePendingPostScrollLom();
  bool get hasPendingPostScrollCapture;

  /// Current LOM id used to bind events to their screen snapshot.
  String? get currentLomRef;

  /// Resolves the LOM state to freeze when a pointer starts.
  ({String lomRef, bool isResolved}) resolveLomStateForPointerDown();

  void recordLom(LomAbstract? lom);
  void recordAction(ActionEvent action);
  void recordExploration(ExplorationEvent exploration);

  Chunk? extractChunk();
}

@internal
class NoOpContext implements SessionRecorderContext {
  NoOpContext._();
  static final _instance = NoOpContext._();
  factory NoOpContext() => _instance;

  @override
  void start() {}
  @override
  void dispose() {}
  @override
  String? get currentLomRef => null;
  @override
  bool get hasPendingPostScrollCapture => false;
  @override
  ({String lomRef, bool isResolved}) resolveLomStateForPointerDown() =>
      (lomRef: '', isResolved: false);
  @override
  void recordAction(ActionEvent action) {}
  @override
  void recordExploration(ExplorationEvent exploration) {}
  @override
  void recordLom(LomAbstract? lom) {}
  @override
  void captureTree(bool comesFromNavigation, {bool bypassCooldown = false}) {}
  @override
  ValueListenable<LomAbstract?>? get notifier => null;
  @override
  Chunk? extractChunk() => null;
  @override
  void setCurrentlyNavigating() {}
  @override
  void setScrollActive(bool isActive) {}
  @override
  void markPostScrollCapturePending() {}
  @override
  void capturePendingPostScrollLom() {}
}

@internal
class ContextImpl implements SessionRecorderContext {
  final SessionRecorderEngine _engine;

  ContextImpl(this._engine) {
    _currentSession = Session();
    _currentChunk = _createChunk();
  }

  late Chunk _currentChunk;
  late Session _currentSession;
  LomAbstract? _currentLom;

  TreeDetector? _detector;

  /// Exposes the local LOM state for regression tests.
  @visibleForTesting
  LomAbstract? get currentLomForTest => _currentLom;

  @override
  void start() {
    if (_detector?.isRunning == true) return;

    _detector = TreeDetector(engine: _engine);
    _detector!.detect();
  }

  @override
  void dispose() {
    _detector?.dispose();
    _detector = null;
    _currentLom = null;
    _currentChunk = _createChunk();
  }

  @override
  String? get currentLomRef => _currentLom?.id;

  @override
  bool get hasPendingPostScrollCapture =>
      _detector?.hasPendingPostScrollCapture ?? false;

  @override
  ({String lomRef, bool isResolved}) resolveLomStateForPointerDown() =>
      _detector?.resolveLomStateForPointerDown() ??
      (lomRef: currentLomRef ?? '', isResolved: false);

  @override
  void recordAction(ActionEvent action) {
    _currentChunk.addActionEvent(action);
    _detector?.armInteractionConsequence();
    _engine.controller.pingInactivity();
  }

  @override
  void recordExploration(ExplorationEvent exploration) {
    _currentChunk.addExplorationEvent(exploration);
    _engine.controller.pingInactivity();
  }

  @override
  void recordLom(LomAbstract? lom) {
    if (lom == null) return;

    _currentLom = lom;

    if (lom is LocalLomRef) return;

    _currentChunk.addLom(lom);
  }

  @override
  void captureTree(bool comesFromNavigation, {bool bypassCooldown = false}) =>
      _detector?.captureTree(
        comesFromNavigation,
        bypassCooldown: bypassCooldown,
      );

  @override
  void setCurrentlyNavigating() => _detector?.setCurrentlyNavigating();

  @override
  void setScrollActive(bool isActive) => _detector?.setScrollActive(isActive);

  @override
  void markPostScrollCapturePending() =>
      _detector?.markPostScrollCapturePending();

  @override
  void capturePendingPostScrollLom() =>
      _detector?.capturePendingPostScrollLom();

  @override
  ValueNotifier<LomAbstract?>? get notifier => _detector?.notifier;

  @override
  Chunk? extractChunk() {
    if (_currentChunk.isChunkEmpty) return null;

    final chunk = _currentChunk;

    _currentChunk = _createChunk();

    return chunk;
  }

  Chunk _createChunk() => Chunk()..sId = _currentSession.id;
}
