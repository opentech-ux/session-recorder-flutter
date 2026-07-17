import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

/// Configuration for the session context.
///
/// Pass an instance to `SessionRecorder.init` before `runApp`.
///
/// ### Example
///
/// ```dart
/// final config = SessionRecorderConfig(endpoint: 'https://demo-client.ux-key.com endpoint');
/// SessionRecorder.init(config);
/// ```
/// See also
///  - `[SessionLogger]`: which defines the logging mechanism for the SDK's
/// internal logs.
@immutable
class SessionRecorderConfig {
  /// The backend endpoint that receives session data.
  ///
  /// This URL is provided by the the __company__ and must support **POST**
  /// requests for session uploads.
  ///
  /// __If empty or not matching the official endpoint format,
  /// `[validate]` throws a `[FormatException]`. During `[SessionRecorder.init]`,
  /// invalid configuration makes the SDK fall back to no-op mode.__
  final String endpoint;

  /// Whether to show the debug logs.
  ///
  /// __Only used for debug purpose.__
  final bool debugLog;

  /// Paints captured `[Root]` rectangles as a semi-transparent overlay.
  ///
  /// Useful during development to verify which widgets are being captured.
  /// Only active in debug builds regardless of this value.
  final bool debugShowTree;

  /// Force sending data to the endpoint even in debug mode.
  ///
  /// This will always be `[true]` in release mode. In debug mode, it will
  /// only be true if `[debugSendSession]` is explicitly set to true.
  final bool shouldSend;

  ///{@macro session_logger}
  final SessionLoggerCallback logger;

  static final RegExp _endpointRegExp = RegExp(
    r'^https://[a-zA-Z0-9-]+\.ux-key\.com/endpoint$',
  );

  const SessionRecorderConfig({
    this.endpoint = "",
    this.debugLog = false,
    this.debugShowTree = false,

    /// Default to `[false]` to avoid sending to the `[endpoint]` the data
    /// captured in debug mode.
    /// Enable this ONLY to send TESTING data. Normally you do not
    /// have to enable this.
    bool debugSendSession = false,
    SessionLoggerCallback? logger,
  }) : shouldSend = kReleaseMode || debugSendSession,
       logger = logger ?? defaultSessionLogger;

  void validate() {
    if (!_endpointRegExp.hasMatch(endpoint)) {
      throw FormatException(
        'Invalid Endpoint. The expected format is `https://[subdomain].ux-key.com/endpoint`, where the subdomain may only contain letters, numbers, and hyphens.',
      );
    }
  }
}
