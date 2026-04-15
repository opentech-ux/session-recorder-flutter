import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

@internal
class SessionRecorderReporter {
  final SessionRecorderEngine _engine;
  SessionRecorderReporter(this._engine);

  /// The active periodic `[Timer]`, or `null` if no timer is running.
  Timer? _timer;

  /// The interval used for the periodic timer ticks.
  ///
  /// __Defaults to 10 seconds__
  final Duration _interval = Duration(seconds: 10);

  late final IOClient _httpClient = IOClient(
    HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => kDebugMode,
  );

  /// Starts the session record timer subsystem.
  void start() {
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

  /// Validates the [Chunk] before to send it into the server
  Future<void> _flush() async {
    final chunk = _engine.context.extractChunk();

    if (chunk == null) return;

    if (!_engine.config.shouldSend) {
      if (_engine.config.debugLog) {
        SessionLogger.verbose("Not send it cause `shouldSend` is [false]");
      }
      return;
    }

    await _send(chunk);
  }

  /// Periodic callback that sends the [Chunk] to the server.
  Future<void> _send(Chunk chunk) async {
    final body = chunk.toJson();
    final uri = Uri.parse(_engine.config.endpoint);

    try {
      final response = await _httpClient.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: body,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Server responded with status ${response.statusCode}',
          uri: uri,
        );
      }

      SessionLogger.info("Sended Data - SESSION RECORDER");
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
  }
}
