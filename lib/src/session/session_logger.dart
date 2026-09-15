import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/session_recorder_flutter.dart';

enum SessionLogLevel { error, warning, info, verbose }

typedef SessionLoggerCallback = void Function(
  SessionLogLevel level,
  String message, {
  Object? error,
  StackTrace? stackTrace,
});

void defaultSessionLogger(
  SessionLogLevel level,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  if (kReleaseMode) return;

  final prefix = switch (level) {
    SessionLogLevel.verbose => '-',
    SessionLogLevel.info => '>',
    SessionLogLevel.warning => '!',
    SessionLogLevel.error => '!!',
  };

  developer.log(
    message,
    name: "SessionRecorder $prefix",
    error: error,
    stackTrace: stackTrace,
  );
}

/// {@template session_logger}
/// Defines the delegation mechanism for the SDK's internal logs.
///
/// This prevents console pollution and gives the client application absolute
/// control over how, when, and where logs are stored or displayed.
/// Exceptions thrown by the callback are contained and never reported back
/// through that callback.
///
/// __Common use cases:__
/// * __Default behavior:__ If a custom logger is not provided, the SDK uses
///   a safe, native logger that is automatically silenced in production
///   (`kReleaseMode`).
/// * __Third-party integration:__ Allows routing SDK messages to external
///   logging packages that the application is already using (e.g., `logger`,
///   `talker`, `datadog`).
///
/// ### __Example of custom integration:__
/// ```dart
/// SessionRecorderConfig(
///   debugLog: true,
///   logger: (level, message, {error, stackTrace}) {
///     if (level == SessionLogLevel.error) {
///       Crashlytics.instance.recordError(error, stackTrace, reason: message);
///     } else {
///       myCustomConsole.log('[$level] SDK: $message');
///     }
///   },
/// )
/// ```
/// {@endtemplate}
class SessionLogger {
  static late SessionRecorderConfig _config;

  static SessionLoggerCallback _delegate = defaultSessionLogger;
  static bool _isLogging = false;

  static void configure({required SessionRecorderConfig configuration}) {
    _delegate = configuration.logger;
    _config = configuration;
  }

  @internal
  static void info(String message) {
    if (_config.debugLog) {
      _log(SessionLogLevel.info, message);
    }
  }

  @internal
  static void verbose(String message) {
    if (_config.debugLog) {
      _log(SessionLogLevel.verbose, message);
    }
  }

  @internal
  static void warning(String message) {
    if (_config.debugLog) {
      _log(SessionLogLevel.warning, message);
    }
  }

  @internal
  static void error(String message, [Object? e, StackTrace? s]) {
    if (!_config.debugLog && kReleaseMode) return;

    _log(SessionLogLevel.error, message, error: e, stackTrace: s);
  }

  static void _log(
    SessionLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_isLogging) return;
    _isLogging = true;
    try {
      _delegate(level, message, error: error, stackTrace: stackTrace);
    } catch (_) {
      // Client diagnostics must not interrupt recording or recursively log
      // their own failure through the same callback.
    } finally {
      _isLogging = false;
    }
  }
}
