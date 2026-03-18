import 'package:meta/meta.dart';

@immutable
class SessionRecorderConfig {
  /// The backend endpoint (URI) that receives session data.
  ///
  /// This URL is provided by the the __company__ and must support [POST]
  /// requests for session uploads.
  final String endpoint;

  /// Whether to show the debug logs.
  ///
  /// __Only used for debug purpose.__
  final bool debugLog;

  /// Configuration object required by [SessionRecorder.init].
  ///
  /// This class provides the set of parameters that the session recording
  /// service needs to operate:
  ///
  /// {@macro session_record}
  ///
  /// The `endpoint` is required and must not be null. The service will throw
  /// a [ArgumentError] if the provided `endpoint` is not correct.
  const SessionRecorderConfig({this.endpoint = "", this.debugLog = false});
}
