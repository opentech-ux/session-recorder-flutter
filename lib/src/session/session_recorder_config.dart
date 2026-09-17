import 'package:flutter/foundation.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

/// Configuration for the session context.
///
/// Pass an instance to `SessionRecorder.init` before `runApp`.
///
/// ### Example
///
/// ```dart
/// final config = SessionRecorderConfig(
///   endpoint: 'https://demo-client.ux-key.com/endpoint',
/// );
/// SessionRecorder.init(config);
/// ```
/// See also
///  - `[SessionLogger]`: which defines the logging mechanism for the SDK's
/// internal logs.
@immutable
class SessionRecorderConfig {
  /// The backend endpoint that receives session data.
  ///
  /// Must be a non-empty, valid absolute HTTP or HTTPS URI with a host.
  /// Localhost and IP-based endpoints are allowed. The endpoint must support
  /// **POST** requests for session uploads.
  ///
  /// [validate] throws a [FormatException] for invalid endpoints.
  /// `SessionRecorder.init` validates before starting the engine in every build
  /// mode, contains initialization failures and leaves the SDK in no-op mode.
  /// Errors are reported through SessionLogger; console output is not guaranteed
  /// (the default logger is silent in Release).
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

  /// Optional authoritative logical screen name, anonymized immediately.
  ///
  /// Null results or synchronous errors mean unknown, without an observer
  /// fallback. Called for initial/navigation captures and observer callbacks,
  /// not every build or input event. Keep this synchronous getter cheap and
  /// side-effect free. Return a stable, non-sensitive identifier, not arguments.
  final String? Function()? screenNameProvider;

  /// Force sending data to the endpoint even in debug mode.
  ///
  /// This will always be `[true]` in release mode. In debug mode, it will
  /// only be true if `[debugSendSession]` is explicitly set to true.
  final bool shouldSend;

  ///{@macro session_logger}
  final SessionLoggerCallback logger;

  const SessionRecorderConfig({
    this.endpoint = "",
    this.debugLog = false,
    this.debugShowTree = false,
    this.screenNameProvider,

    /// Default to `[false]` to avoid sending to the `[endpoint]` the data
    /// captured in debug mode.
    /// Enable this ONLY to send TESTING data. Normally you do not
    /// have to enable this.
    bool debugSendSession = false,

    ///{@macro session_logger}
    SessionLoggerCallback? logger,
  })  : shouldSend = kReleaseMode || debugSendSession,
        logger = logger ?? defaultSessionLogger;

  void validate() {
    final value = endpoint.trim();

    if (value.isEmpty) {
      throw const FormatException(
        'Endpoint must not be empty.',
      );
    }

    final uri = Uri.tryParse(value);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException(
        'Endpoint must be a valid absolute URI.',
      );
    }

    final scheme = uri.scheme.toLowerCase();

    if (scheme != 'http' && scheme != 'https') {
      throw const FormatException(
        'Endpoint must use the http or https scheme.',
      );
    }
  }
}
