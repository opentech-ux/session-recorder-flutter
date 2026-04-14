import 'package:meta/meta.dart';

import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC FACADE
// Only init() are exposed to end users.
// ─────────────────────────────────────────────────────────────────────────────

/// {@template session_record_service}
/// Main tracker coordinator for session interaction recording and tree capture.
///
/// This class is the primary entry point of the package and the only object
/// consumers are intended to call `[init()]` and `[configure()]` method from
/// `[main()]`.
///
/// {@template session_record}
/// ### Example usage
/// ```dart
/// void main() {
///   // Important to add it before calling init method
///   WidgetsFlutterBinding.ensureInitialized();
///
///   final config = SessionRecorderConfig(
///     endpoint: 'https://api.example.com/endpoint',
///     debugLog: true,
///   );
///
///   SessionRecorder.init(config);
///
///   runApp(MyApp());
/// }
/// ```
///
/// Or also could be as :
/// ```dart
/// void main() {
///   // Important to add it before calling init method
///   WidgetsFlutterBinding.ensureInitialized();
///
///   SessionRecorder.init(
///     SessionRecorderConfig(
///       endpoint: 'https://api.example.com/endpoint',
///       debugLog: true,
///     ),
///   );
///
///   runApp(MyApp());
/// }
/// ```
///
/// There is **no need to wrap it inside**
/// `[WidgetsBinding.instance.addPostFrameCallback()]`, since `[init()]`
///    already ensures the call is deferred until the first frame is rendered.
/// {@endtemplate}
///
/// This method performs several heavy operations.
/// Therefore, it **must not be called from any widget build method,
/// hot path, or frequent callback**, doing so may cause UI freezes
/// or dropped frames.
///
/// Call `[init()]` **only once**, and **only after** the app’s root widget
/// (`MaterialApp`, `CupertinoApp`, etc.) has been fully mounted.
///
/// {@endtemplate}
///
/// See also :
///  - `[SessionRecorderConfig]`: which defines the session configuration.
///  - `[SessionLogger]`: which defines the logging mechanism for the SDK's
/// internal logs.
@sealed
class SessionRecorder {
  ///{@macro session_record_service}
  SessionRecorder._();

  static SessionRecorderEngineInternal _engine = NoOpSessionRecorderEngine();

  /// __DO NOT USE - INTERNAL SDK API__
  ///
  /// This getter is exposed solely for internal communication within the SDK
  /// (e.g., between the Engine and the Collectors).
  ///
  /// Accessing or manipulating this engine directly from your application code
  /// bypasses all safety checks. Doing so will corrupt the Session Recorder
  /// state, cause unexpected memory leaks, and potentially crash the host
  /// application.
  @internal
  static SessionRecorderEngineInternal get engine => _engine;

  /// Initializes the session record.
  ///
  /// This method performs the initial setup required for the widget-tree
  /// capture service:
  ///
  ///  - Ensure to call it from application startup in `[main()]`.
  ///  - Write `[WidgetsFlutterBinding.ensureInitialized();]` before this method.
  ///  - The scheduled listeners run after frames; avoid calling `[init()]` during
  ///  an unstable `[build()]`.
  ///  - Only set it **once**.
  ///
  /// {@macro session_record}
  ///
  /// See also
  ///  - `[SessionRecorderConfig]`: More information on what can be shared.
  ///
  /// Throws `[ArgumentError]` if `[SessionRecorderConfig]` are invalid.
  static void init(SessionRecorderConfig config) {
    if (_engine.isEnabled) {
      SessionLogger.warning("SessionRecorder already initialized");
      return;
    }

    try {
      // TODO uncomment this :
      // config.validate();

      SessionLogger.configure(configuration: config);

      _engine = SessionRecorderEngine(config);
      _engine.start();
    } catch (e, stack) {
      _engine = NoOpSessionRecorderEngine();
      SessionLogger.error('Cannot initialized the SDK', e, stack);
    }
  }
}
