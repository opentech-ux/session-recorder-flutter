import 'package:session_recorder_flutter/session_recorder.dart';
import 'package:session_recorder_flutter/src/constants/version_constant.dart';

import '../models/models.dart'
    show Chunk, LomAbstract, ExplorationEvent, ActionEvent;

class ChunkNotInitializedException implements Exception {
  final String message;
  ChunkNotInitializedException([this.message = 'Chunk not initialized']);
  @override
  String toString() => 'ChunkNotInitializedException: $message';
}

/// {@template interaction_delegate}
/// A delegate responsible for managing and processing a chunk session.
///
/// The [ChunkDelegate] manages all the logic for inserting, initializing, and
/// deleting the attributes of a [Chunk], as well as the higher-level
/// interaction logic.
///
/// Typically initialized internally by [SessionRecorder] and managed
/// in [InteractionDelegate].
/// {@endtemplate}
class ChunkDelegate {
  static final ChunkDelegate _instance = ChunkDelegate._internal();
  factory ChunkDelegate() => _instance;
  ChunkDelegate._internal();

  Chunk? _chunk;

  bool get hasChunk => _chunk != null;

  Chunk get chunk {
    final chunk = _chunk;
    if (chunk == null) throw ChunkNotInitializedException();
    return chunk;
  }

  bool get isChunkEmpty =>
      _chunk!.loms.isEmpty &&
      _chunk!.explorationEvents.isEmpty &&
      _chunk!.actionsEvents.isEmpty;

  /// Creates and assigns a new [Chunk] instance using the given `sessionId`.
  void init(String sessionId) {
    _chunk = Chunk(
      libraryVersion: libraryVersion,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sId: sessionId,
      loms: [],
      explorationEvents: [],
      actionsEvents: [],
    );
  }

  /// Ensure if the `_chunk` is not [null].
  void _ensureInitialized() {
    if (_chunk == null) throw ChunkNotInitializedException();
  }

  /// Add a [LomAbstract] to the [Chunk].
  ///
  /// Could be a [Lom] or [LomRef] classes.
  void addLom(LomAbstract lom) {
    _ensureInitialized();

    _chunk = _chunk!.copyWith(
      loms: List<LomAbstract>.from(_chunk!.loms)..add(lom),
    );
  }

  /// Add a [ExplorationEvent] list to the [Chunk]
  void addExplorationEvents(List<ExplorationEvent> explorationEvents) {
    _ensureInitialized();

    _chunk = _chunk!.copyWith(
      explorationEvents: List<ExplorationEvent>.from(_chunk!.explorationEvents)
        ..addAll(explorationEvents),
    );
  }

  /// Add a [ActionEvent] to the [Chunk]
  void addActionEvent(ActionEvent actionEvent) {
    _ensureInitialized();

    _chunk = _chunk!.copyWith(
      actionsEvents: List<ActionEvent>.from(_chunk!.actionsEvents)
        ..add(actionEvent),
    );
  }

  /// Clears the `_chunk`
  void clearChunk() => _chunk = null;
}
