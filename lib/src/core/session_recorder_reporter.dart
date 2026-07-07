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

  /// Small cap to avoid memory growth during network failures.
  static const int _maxPendingChunks = 3;

  /// One retry keeps the reporter resilient without blocking the app.
  static const int _maxRetries = 1;

  late final IOClient _httpClient = IOClient(
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
    _httpClient.close();
  }

  /// Validates the [Chunk] before to send it into the server.
  Future<void> _flush() async {
    if (_isFlushing) return;
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
      _pendingChunks.removeFirst();
      SessionLogger.warning("Dropping oldest pending chunk");
    }

    _pendingChunks.addLast(_QueuedChunk(chunk));
  }

  /// Sends queued chunks until one needs to wait for a retry.
  Future<void> _drainQueue() async {
    while (_pendingChunks.isNotEmpty) {
      final queued = _pendingChunks.first;
      final sent = await _send(queued.chunk);

      if (_isClosed) return;

      if (sent) {
        _pendingChunks.removeFirst();
        continue;
      }

      queued.retries += 1;
      if (queued.retries > _maxRetries) {
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
      final response = await _httpClient.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: body,
      ).timeout(_requestTimeout);

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
}

/// A chunk kept in memory with its retry count.
class _QueuedChunk {
  final Chunk chunk;
  int retries = 0;

  _QueuedChunk(this.chunk);
}
