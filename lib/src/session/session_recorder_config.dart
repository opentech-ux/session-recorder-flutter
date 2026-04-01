import 'package:flutter/foundation.dart';

/// Configuration for the session recorder.
///
/// Pass an instance to `[SessionRecorder.configure]` before calling
/// `[SessionRecorderWidget]` or starting the app.
///
/// ### Example
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   SessionRecorder.instance.configure(
///     SessionRecorderConfig(
///       endpoint: 'https://api.com/endpoint',
///       debugLog: true,
///     ),
///   );
///
///   runApp(const App());
/// }
/// ```
@immutable
class SessionRecorderConfig {
  /// The backend endpoint that receives session data.
  ///
  /// This URL is provided by the the __company__ and must support **POST**
  /// requests for session uploads.
  ///
  /// __If empty or invalid URL, a `[FormatException]` is show__
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

  /// Determines whether the session data should be sent to the server.
  /// This will always be `[true]` in release mode. In debug mode, it will
  /// only be true if `[debugSendSession]` is explicitly set to true.
  final bool shouldSend;

  const SessionRecorderConfig({
    this.endpoint = "",
    this.debugLog = false,
    this.debugShowTree = false,

    /// Default to `[false]` to avoid sending to the `endpoint` the data
    /// captured in debug mode.
    /// Enable this ONLY to send TESTING data. Normally you do not
    /// have to enable this.
    bool debugSendSession = false,
  }) : shouldSend = kReleaseMode || debugSendSession;
}
