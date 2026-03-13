import 'dart:developer' as developer;

import 'package:session_recorder_flutter/session_recorder.dart';
import 'package:session_recorder_flutter/src/models/models.dart';

class SessionLogger {
  static final SessionRecorderConfig _config = SessionRecorder.instance.config;

  static mlog(String message) {
    if (_config.debugLog) developer.log(message);
  }

  static elog(String message, [Object? error, StackTrace? stack]) {
    if (_config.debugLog) {
      developer.log(
        message,
        name: 'ERROR',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
    }
  }
}
