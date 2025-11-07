import 'package:uuid/uuid.dart';

import '../models/models.dart' show Session;

class SessionNotInitializedException implements Exception {
  final String message;
  SessionNotInitializedException([this.message = 'Session not initialized']);
  @override
  String toString() => 'SessionNotInitializedException: $message';
}

/// {@template interaction_delegate}
/// A delegate responsible for managing and processing a [Session].
///
/// The [SessionDelegate] is used to initialize a new [Session] with a [Uuid]
/// version 4 identifier, as well as the higher-level interaction logic.
///
/// Typically initialized internally by [SessionRecorder].
/// {@endtemplate}
class SessionDelegate {
  static final SessionDelegate _instance = SessionDelegate._internal();
  factory SessionDelegate() => _instance;
  SessionDelegate._internal();

  Session? _session;

  bool get hasSession => _session != null;

  Session get session {
    final session = _session;
    if (session == null) throw SessionNotInitializedException();
    return session;
  }

  void init() {
    final String sId = Uuid().v4();
    _session = Session(id: sId);
  }

  void _ensureInitialized() {
    if (_session == null) throw SessionNotInitializedException();
  }

  String getId() {
    _ensureInitialized();

    return _session!.id;
  }
}
