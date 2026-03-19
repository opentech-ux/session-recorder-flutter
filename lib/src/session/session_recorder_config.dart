import 'package:meta/meta.dart';

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
  /// This URL is provided by the the __company__ and must support [POST]
  /// requests for session uploads.
  ///
  /// __If empty or invalid URL, a `[FormatException]` is show__
  final String endpoint;

  /// Whether to show the debug logs.
  ///
  /// __Only used for debug purpose.__
  final bool debugLog;

  const SessionRecorderConfig({this.endpoint = "", this.debugLog = false});
}
