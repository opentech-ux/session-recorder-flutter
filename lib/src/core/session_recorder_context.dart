import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';

import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';

/// Internal contract for session state, tree analysis, and data recording.
@internal
abstract interface class SessionRecorderContext {
  void start();
  void dispose();

  void captureTree(bool comesFromNavigation);
  ValueListenable<LomAbstract?>? get notifier;
  void setCurrentlyNavigating();
  void setScrollActive(bool isActive);

  /// Current LOM id used to bind events to their screen snapshot.
  String? get currentLomRef;

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
  void recordAction(ActionEvent action) {}
  @override
  void recordExploration(ExplorationEvent exploration) {}
  @override
  void recordLom(LomAbstract? lom) {}
  @override
  void captureTree(bool comesFromNavigation) {}
  @override
  ValueListenable<LomAbstract?>? get notifier => null;
  @override
  Chunk? extractChunk() => null;
  @override
  void setCurrentlyNavigating() {}
  @override
  void setScrollActive(bool isActive) {}
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
  void recordAction(ActionEvent action) {
    _currentChunk.addActionEvent(action);
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

    SessionLogger.verbose("LOM SAVED - ${lom.id}");
  }

  @override
  void captureTree(bool comesFromNavigation) =>
      _detector?.captureTree(comesFromNavigation);

  @override
  void setCurrentlyNavigating() => _detector?.setCurrentlyNavigating();

  @override
  void setScrollActive(bool isActive) => _detector?.setScrollActive(isActive);

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
