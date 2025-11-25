class SessionRecorderParams {
  /// The backend endpoint (URI) that receives session data.
  ///
  /// This URL is provided by the the __company__ and must support [POST]
  /// requests for session uploads.
  final String? endpoint;

  /// Whether to completely disable the session recording behavior.
  ///
  /// When set to [true], all internal logic for behavior tracking and
  /// network communication is bypassed.
  /// This is useful for development, testing, or when you need to temporarily
  /// stop analytics without removing the widget or service initialization.
  ///
  /// __Defaults to [false]__
  final bool disable;

  /// Configuration object required by [SessionRecorder.init].
  ///
  /// This class provides the set of parameters that the session recording
  /// service needs to operate:
  ///
  /// {@macro session_record}
  ///
  /// The `endpoint` is required and must not be null. The service will throw
  /// a [ArgumentError] if the provided `endpoint` is not correct.
  SessionRecorderParams({this.endpoint, this.disable = false});
}
