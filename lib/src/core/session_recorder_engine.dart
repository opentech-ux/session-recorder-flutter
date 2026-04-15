import 'package:flutter/foundation.dart';

import 'package:session_recorder_flutter/src/core/session_recorder_controller.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_context.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

@internal
abstract interface class SessionRecorderEngineInternal {
  void start();
  bool get isEnabled;
  SessionRecorderConfig get config;
  SessionRecorderContext get context;
  SessionRecorderController get controller;
}

@internal
class NoOpSessionRecorderEngine implements SessionRecorderEngineInternal {
  NoOpSessionRecorderEngine._();
  static final _instance = NoOpSessionRecorderEngine._();
  factory NoOpSessionRecorderEngine() => _instance;

  @override
  void start() {}
  @override
  bool get isEnabled => false;
  @override
  final SessionRecorderConfig config = SessionRecorderConfig();
  @override
  final SessionRecorderContext context = NoOpContext();
  @override
  final SessionRecorderController controller = NoOpController();
}

@internal
class SessionRecorderEngine implements SessionRecorderEngineInternal {
  SessionRecorderEngine(this.config) {
    context = ContextImpl(this);
    controller = ControllerImpl(this);
    _isEnabled = true;
  }

  bool _isEnabled = false;

  @override
  bool get isEnabled => _isEnabled;

  @override
  final SessionRecorderConfig config;
  @override
  late final SessionRecorderContext context;
  @override
  late final SessionRecorderController controller;

  @override
  void start() {
    context.start();
    controller.startReporting();

    SessionLogger.info("SESSION RECORDER INITIALIZED");
  }
}
