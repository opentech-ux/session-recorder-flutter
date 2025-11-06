import 'package:flutter/material.dart';

class SessionRecordParams {
  /// The [GlobalKey] attached to the app’s [Navigator].
  ///
  /// Used internally by the recording service to access navigation context
  /// and capture widget tree snapshots.
  final GlobalKey<NavigatorState>? key;

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

  /// Configuration object required by [SessionRecord.init].
  ///
  /// This class provides the set of parameters that the session recording
  /// service needs to operate:
  ///
  /// {@macro session_record}
  ///
  /// Both fields are required and must not be null. The service will throw
  /// a [ArgumentError] if the provided key is not yet mounted at initialization
  /// time.
  SessionRecordParams({this.key, this.endpoint, this.disable = false});
}
