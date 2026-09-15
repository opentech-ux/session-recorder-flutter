import 'package:session_recorder_flutter/src/session/session_logger.dart';

/// Runs SDK-owned synchronous work only, never a host callback or async work.
bool runRecorderCallback(String operation, void Function() callback) {
  try {
    callback();
    return true;
  } catch (error, stackTrace) {
    SessionLogger.error(
        'Session Recorder: $operation failed', error, stackTrace);
    return false;
  }
}
