import 'package:meta/meta.dart';

import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC FACADE
// Only init() are exposed to end users.
// ─────────────────────────────────────────────────────────────────────────────

/// {@template session_record_service}
/// Public entry point for Session Recorder.
///
/// Call [init] once from `main`, before `runApp`, then install
/// one `SessionRecorderWidget` around the subtree to capture. Placing the
/// widget in `MaterialApp.builder` or `MaterialApp.router.builder` is
/// recommended. A navigation observer is optional.
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

  /// Initializes the recorder.
  ///
  /// Call this method once from `main`, after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  ///
  /// Install one `SessionRecorderWidget` after initialization. Initialization
  /// errors are caught internally and leave the SDK in no-op mode.
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
