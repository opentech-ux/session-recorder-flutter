import 'package:meta/meta.dart';

import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC FACADE
// Only init() are exposed to end users.
// ─────────────────────────────────────────────────────────────────────────────

/// {@template session_record_service}
/// Public entry point for session interaction recording and tree capture.
///
/// Call [init] once from `main`, before `runApp`, then wrap the application
/// subtree with `SessionRecorderWidget`.
///
/// ### Complete setup
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   final config = SessionRecorderConfig(endpoint: 'https://demo-client.ux-key.com endpoint');
///
///   SessionRecorder.init(config);
///
///   runApp(
///     SessionRecorderWidget(
///       child: const App(),
///     ),
///   );
/// }
/// ```
///
/// `WidgetsFlutterBinding.ensureInitialized()` prepares Flutter. [init]
/// starts the engine, context, reporting, and inactivity tracking.
/// `SessionRecorderWidget` installs the collectors, provides the application
/// subtree used for captures, and requests one initial capture after the first
/// frame. It does not start the context or reporting again.
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

  /// Initializes session recording.
  ///
  /// Call this method once from `main`, after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  ///
  /// This starts the engine, context, reporting, and inactivity tracking.
  /// The initial capture after the first frame is requested by
  /// `SessionRecorderWidget`; applications do not need to defer [init].
  ///
  /// Configuration and initialization errors are caught internally. When
  /// initialization fails, the SDK continues in no-op mode.
  ///
  /// See also
  ///  - `[SessionRecorderConfig]`: More information on what can be shared.
  static void init(SessionRecorderConfig config) {
    if (_engine.isEnabled) {
      SessionLogger.warning("SessionRecorder already initialized");
      return;
    }

    try {
      SessionLogger.configure(configuration: config);

      // TODO: Re-enable before publishing. Kept disabled for local endpoint tests.
      // config.validate();

      _engine = SessionRecorderEngine(config);
      _engine.start();
    } catch (e, stack) {
      _engine = NoOpSessionRecorderEngine();
      SessionLogger.error('Cannot initialized the SDK', e, stack);
    }
  }
}
