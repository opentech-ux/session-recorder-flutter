import 'package:uuid/uuid.dart';

/// Accumulates session data captured during one reporting window.
class Session {
  /// Unique identifier for this reporting session.
  final String id;

  Session() : id = Uuid().v4();

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'id': id};
  }

  @override
  String toString() => 'Session(id: $id)';
}
