import 'package:uuid/uuid.dart';

class Session {
  final String id;

  Session() : id = Uuid().v4();

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'id': id};
  }

  @override
  String toString() => 'Session(id: $id)';
}
