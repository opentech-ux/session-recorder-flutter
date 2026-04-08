import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/io_client.dart';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_controller_internal.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';
import 'package:session_recorder_flutter/src/tree/tap_tree_resolver.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

@internal
abstract interface class SessionRecorderEngineInternal {
  void start();
  bool get isEnabled;
  SessionRecorderConfig get config;
  SessionRecorderInternal get recorder;
  SessionControllerInternal get controller;
}

@internal
class NoOpSessionRecorderEngine implements SessionRecorderEngineInternal {
  NoOpSessionRecorderEngine._();
  static final _instance = NoOpSessionRecorderEngine._();
  factory NoOpSessionRecorderEngine() => _instance;

  @override
  void start() {}
  @override
  bool get isEnabled => false;
  @override
  final SessionRecorderConfig config = SessionRecorderConfig();
  @override
  final SessionRecorderInternal recorder = NoOpRecorder();
  @override
  final SessionControllerInternal controller = NoOpController();
}

@internal
class SessionRecorderEngine implements SessionRecorderEngineInternal {
  SessionRecorderEngine(this.config) {
    recorder = _RecorderImpl(this);
    controller = _ControllerImpl(this);
    _isEnabled = true;
  }

  bool _isEnabled = false;

  @override
  bool get isEnabled => _isEnabled;

  @override
  final SessionRecorderConfig config;
  @override
  late final SessionRecorderInternal recorder;
  @override
  late final SessionControllerInternal controller;

  @override
  void start() {
    recorder.start();
    controller.startReporting();

    SessionLogger.info("SESSION RECORDER INITIALIZED");
  }
}

class _RecorderImpl implements SessionRecorderInternal {
  final SessionRecorderEngine _engine;
  _RecorderImpl(this._engine) {
    _currentSession = Session();
    _currentChunk = Chunk();
    _currentChunk.sId = _currentSession.id;
  }

  final TapTreeFinder _finder = const TapTreeFinder();

  late Rect _screenViewport = Rect.zero;
  late Rect _scrollPhysicalBounds = Rect.zero;
  late Rect _scrollVirtualCanvas = Rect.zero;

  late Chunk _currentChunk;
  late Session _currentSession;
  late LomAbstract _currentLom;

  Element? _currentRouteElement;

  TreeDetector? _detector;

  @override
  void start() {
    if (_detector?.isRunning == true) return;

    _detector = TreeDetector(engine: _engine);
    _detector!.detect();
  }

  @override
  Rect get screenViewport => _screenViewport;
  @override
  void setScreenViewport(Rect sV) => _screenViewport = sV;

  @override
  Rect get scrollPhysicalBounds => _scrollPhysicalBounds;
  @override
  void setScrollPhysicalBounds(Rect sPB) => _scrollPhysicalBounds = sPB;

  @override
  Rect get scrollVirtualCanvas => _scrollVirtualCanvas;
  @override
  void setScrollVirtualCanvas(Rect sVC) => _scrollVirtualCanvas = sVC;

  @override
  Rect resolveViewport(Offset position) {
    if (_scrollPhysicalBounds.contains(position)) return _scrollVirtualCanvas;

    return _screenViewport;
  }

  @override
  void recordAction(ActionEvent action) {
    _currentChunk.addActionEvent(action);
    _engine.controller.pingInactivity();
  }

  @override
  void recordExploration(ExplorationEvent exploration) {
    _currentChunk.addExplorationEvent(exploration);
    _engine.controller.pingInactivity();
  }

  @override
  void recordLom(LomAbstract lom) {
    _currentLom = lom;
    _currentChunk.addLom(lom);

    SessionLogger.verbose("LOM SAVED - ${lom.id} sign=${lom.signature}");
  }

  @override
  Root? findRoot(Offset position) {
    final tapTreeResult = _finder.find(_currentLom, position);
    return tapTreeResult.didTap ? tapTreeResult.target : null;
  }

  @override
  Element? get currentRouteElement => _currentRouteElement;

  @override
  void captureTree(bool comesFromNavigation) =>
      _detector?.captureTree(comesFromNavigation);

  @override
  void setCurrentRouteElement(Element? element) =>
      _currentRouteElement = element;

  @override
  void setCurrentlyNavigating() => _detector?.setCurrentlyNavigating();

  @override
  ValueNotifier<LomAbstract?>? get notifier => _detector?.notifier;

  @override
  Chunk? extractChunk() {
    if (_currentChunk.isChunkEmpty) return null;

    final chunk = _currentChunk;

    _currentChunk = Chunk();
    _currentChunk.sId = _currentSession.id;

    return chunk;
  }
}

class _ControllerImpl implements SessionControllerInternal {
  final SessionRecorderEngine _engine;
  _ControllerImpl(this._engine);

  final List<SessionNavigatorObserver> _observers = [];

  VoidCallback? _onCollectorInterrupt;

  @override
  bool get isNavigationAttached => _observers.any((o) => o.navigator != null);

  late final InactivityDetector _inactivity = InactivityDetector(
    onActive: startReporting,
    onInactive: stopReporting,
  );
  late final _SessionRecorderReporter _reporter = _SessionRecorderReporter(
    _engine,
  );

  @override
  void registerObserver(SessionNavigatorObserver observer) {
    debugPrint("register observer");
    debugPrint(_observers.toString());
    _observers.removeWhere((obs) => obs.isDisposed);
    if (!_observers.contains(observer)) _observers.add(observer);
    debugPrint(_observers.toString());
  }

  @override
  void pingInactivity() => _inactivity.ping();

  @override
  void startReporting() {
    _reporter.start();
    _inactivity.start();
  }

  @override
  void stopReporting() {
    _reporter.stop();
    _inactivity.stop();
  }

  @override
  void interrupt() => _onCollectorInterrupt?.call();

  @override
  void onInterrupt(VoidCallback? onInterrupt) =>
      _onCollectorInterrupt = onInterrupt;
}

class _SessionRecorderReporter {
  final SessionRecorderEngine _engine;
  _SessionRecorderReporter(this._engine);

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
    final chunk = _engine.recorder.extractChunk();

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

    // final List<LomAbstract> currentLoms = chunk.loms;

    // currentLoms.removeWhere(
    //   (lom) => lastLoms.any((lastLom) => lom.id == lastLom.id),
    // );

    // _lomDelegate.clearLom();
    // _chunkDelegate.init(_sessionDelegate.getId());

    // if (currentLoms.isNotEmpty) {
    //   for (LomAbstract lom in currentLoms) {
    //     _chunkDelegate.addLom(lom);
    //   }
    // }
  }
}
