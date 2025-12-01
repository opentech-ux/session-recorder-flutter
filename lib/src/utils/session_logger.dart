import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class SessionLogger {
  static final bool _debug = kDebugMode;

  static mlog(String message) {
    if (_debug) developer.log(message);
  }

  static elog(String message, [Object? error, StackTrace? stack]) {
    if (_debug) {
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
