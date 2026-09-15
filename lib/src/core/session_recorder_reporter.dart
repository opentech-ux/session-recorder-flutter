import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

@internal
class SessionRecorderReporter {
  /// Runtime services used to read config and extract chunks.
  final SessionRecorderEngineInternal _engine;

  SessionRecorderReporter(
    this._engine, {
    Duration requestTimeout = const Duration(seconds: 5),
  }) : _requestTimeout = requestTimeout;

  /// The active periodic `[Timer]`, or `null` if no timer is running.
  Timer? _timer;

  /// Prevents overlapping HTTP flushes.
  bool _isFlushing = false;
  bool _isClosed = false;

  /// The interval used for the periodic timer ticks.
  ///
  /// __Defaults to 10 seconds__
  final Duration _interval = Duration(seconds: 10);

  /// Maximum time allowed for one HTTP request.
  final Duration _requestTimeout;

  /// Short memory queue for chunks waiting to be sent.
  final Queue<_QueuedChunk> _pendingChunks = Queue<_QueuedChunk>();

  /// Full LOMs rescued when their original chunk is dropped.
  final LinkedHashMap<String, Lom> _rescuedLoms = LinkedHashMap();

  /// Small cap to avoid memory growth during network failures.
  static const int _maxPendingChunks = 3;

  /// Keeps the LOM rescue cache bounded.
  static const int _maxRescuedLoms = 64;

  /// One retry keeps the reporter resilient without blocking the app.
  static const int _maxRetries = 1;

  IOClient? _httpClient;

  /// Owned exclusively by the reporter; recreated lazily after a timeout.
  IOClient get _activeHttpClient => _httpClient ??= IOClient(
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => kDebugMode,
      );

  /// Starts the session record timer subsystem.
  void start() {
    if (_isClosed) return;
    if (_engine.config.endpoint == '') return;
    if (_timer?.isActive ?? false) return;

    _timer = Timer.periodic(_interval, (_) => _flush());
  }

  /// Stops the periodic timer and clears its reference.
  void stop() {
    if (_timer == null) return;

    _timer?.cancel();
    _timer = null;
  }

  /// Permanently closes reporter resources.
  void close() {
    if (_isClosed) return;

    _isClosed = true;
    stop();
    _pendingChunks.clear();
    _rescuedLoms.clear();
    _closeHttpClient();
  }

  void _closeHttpClient() {
    final client = _httpClient;
    _httpClient = null;
    try {
      // IOClient.close force-closes its HttpClient, including active requests.
      client?.close();
    } catch (error, stackTrace) {
      // If cancellation cannot be confirmed, never start another request.
      _isClosed = true;
      stop();
      _pendingChunks.clear();
      _rescuedLoms.clear();
      SessionLogger.error('HTTP client cleanup failed', error, stackTrace);
    }
  }

  /// Validates the [Chunk] before to send it into the server.
  Future<void> _flush() async {
    if (_isClosed || _isFlushing) return;
    _isFlushing = true;

    try {
      final chunk = _engine.context.extractChunk();

      if (!_engine.config.shouldSend) {
        if (_engine.config.debugLog) {
          SessionLogger.verbose("Not send it cause `shouldSend` is [false]");
        }
        return;
      }

      if (chunk != null) _enqueue(chunk);

      await _drainQueue();
    } finally {
      _isFlushing = false;
    }
  }

  @visibleForTesting
  Future<void> flushForTest() => _flush();

  @visibleForTesting
  int get pendingChunksForTest => _pendingChunks.length;

  /// Adds a chunk to the bounded memory queue.
  void _enqueue(Chunk chunk) {
    if (_pendingChunks.length >= _maxPendingChunks) {
      final dropped = _pendingChunks.removeFirst();
      _rescueFullLoms(dropped.chunk);
      SessionLogger.warning("Dropping oldest pending chunk");
    }

    _pendingChunks.addLast(_QueuedChunk(chunk));
  }

  /// Sends queued chunks until one needs to wait for a retry.
  Future<void> _drainQueue() async {
    while (_pendingChunks.isNotEmpty) {
      final queued = _pendingChunks.first;
      _replaceUnknownRefsWithFullLoms(queued.chunk);

      final sent = await _send(queued.chunk);

      if (_isClosed) return;

      if (sent) {
        _forgetSentFullLoms(queued.chunk);
        _pendingChunks.removeFirst();
        continue;
      }

      queued.retries += 1;
      if (queued.retries > _maxRetries) {
        _rescueFullLoms(queued.chunk);
        _pendingChunks.removeFirst();
        SessionLogger.error("Dropping chunk after retry");
        continue;
      }

      break;
    }
  }

  /// Periodic callback that sends the [Chunk] to the server.
  Future<bool> _send(Chunk chunk) async {
    try {
      final body = chunk.toJson();
      final uri = Uri.parse(_engine.config.endpoint);
      final response = await _activeHttpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: body,
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Server responded with status ${response.statusCode}',
          uri: uri,
        );
      }

      SessionLogger.info("Sended Data - SESSION RECORDER");
      return true;
    } on SocketException catch (e, s) {
      SessionLogger.error("Network error while sending data", e, s);
    } on TimeoutException catch (e, s) {
      // Cancel the physical operation before the queue can retry or release
      // the flush guard. Future.timeout alone only stops waiting.
      _closeHttpClient();
      SessionLogger.error("Request timed out", e, s);
    } on FormatException catch (e, s) {
      SessionLogger.error("Response format error", e, s);
    } on HttpException catch (e, s) {
      SessionLogger.error("HTTP exception", e, s);
    } catch (e, s) {
      SessionLogger.error("Unexpected error sending data", e, s);
    }

    return false;
  }

  /// Keeps full LOMs available for future refs.
  void _rescueFullLoms(Chunk chunk) {
    for (final lom in chunk.loms) {
      if (lom is! Lom || lom.root == null) continue;

      _rememberRescuedLom(lom);
    }
  }

  /// Sends the full LOM again when the server may not know its ref.
  void _replaceUnknownRefsWithFullLoms(Chunk chunk) {
    if (_rescuedLoms.isEmpty) return;

    final referencedRefs = <String>{
      for (final action in chunk.actionsEvents)
        if (action.lomRef.isNotEmpty) action.lomRef,
      for (final exploration in chunk.explorationEvents)
        if (exploration.lomRef.isNotEmpty) exploration.lomRef,
    };
    if (referencedRefs.isEmpty) return;

    final fullRefs = <String>{
      for (final lom in chunk.loms)
        if (lom is Lom) lom.ref,
    };
    final recordRefs = <String>{for (final lom in chunk.loms) lom.ref};

    for (var i = 0; i < chunk.loms.length; i++) {
      final lom = chunk.loms[i];
      if (lom is! LomRef) continue;
      if (!referencedRefs.contains(lom.ref)) continue;
      if (fullRefs.contains(lom.ref)) continue;

      final rescued = _rescuedLoms[lom.ref];
      if (rescued == null) continue;

      chunk.loms[i] = rescued;
      fullRefs.add(lom.ref);
    }

    for (final ref in referencedRefs) {
      if (fullRefs.contains(ref) || recordRefs.contains(ref)) continue;

      final rescued = _rescuedLoms[ref];
      if (rescued == null) continue;

      chunk.loms.add(rescued);
      fullRefs.add(ref);
      recordRefs.add(ref);
    }
  }

  /// Stops rescuing a LOM once a full version was sent.
  void _forgetSentFullLoms(Chunk chunk) {
    for (final lom in chunk.loms) {
      if (lom is Lom) _rescuedLoms.remove(lom.ref);
    }
  }

  void _rememberRescuedLom(Lom lom) {
    _rescuedLoms.remove(lom.ref);
    if (_rescuedLoms.length >= _maxRescuedLoms) {
      _rescuedLoms.remove(_rescuedLoms.keys.first);
    }

    _rescuedLoms[lom.ref] = lom;
  }
}

/// A chunk kept in memory with its retry count.
class _QueuedChunk {
  final Chunk chunk;
  int retries = 0;

  _QueuedChunk(this.chunk);
}
