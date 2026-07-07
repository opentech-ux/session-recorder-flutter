import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_context.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_controller.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_reporter.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';

void main() {
  setUp(() {
    SessionLogger.configure(configuration: const SessionRecorderConfig());
  });

  group('SessionRecorderReporter', () {
    test('does not send when the extracted chunk is empty', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      addTearDown(server.close);

      final context = _FakeContext([null]);
      final reporter = SessionRecorderReporter(
        _FakeEngine(config: _sendConfig(server.endpoint), context: context),
      );

      await reporter.flushForTest();

      expect(context.extractCount, 1);
      expect(server.requestCount, 0);
      expect(reporter.pendingChunksForTest, 0);
    });

    test('does not run concurrent flushes', () async {
      final server = await _TestServer.start((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      addTearDown(server.close);

      final context = _FakeContext([_chunk()]);
      final reporter = SessionRecorderReporter(
        _FakeEngine(config: _sendConfig(server.endpoint), context: context),
      );

      await Future.wait([reporter.flushForTest(), reporter.flushForTest()]);

      expect(context.extractCount, 1);
      expect(server.requestCount, 1);
      expect(reporter.pendingChunksForTest, 0);
    });
  });

  group('Context chunks', () {
    test('keeps new records in the next chunk after extraction', () {
      final engine = SessionRecorderEngine(const SessionRecorderConfig());
      addTearDown(engine.controller.stopReporting);

      final context = engine.context as ContextImpl;

      context.recordAction(_tap());
      final firstChunk = context.extractChunk();

      context.recordExploration(_drag());
      final secondChunk = context.extractChunk();

      expect(firstChunk?.actionsEvents, hasLength(1));
      expect(firstChunk?.explorationEvents, isEmpty);
      expect(secondChunk?.actionsEvents, isEmpty);
      expect(secondChunk?.explorationEvents, hasLength(1));
      expect(secondChunk?.sId, firstChunk?.sId);
    });
  });

  group('LOM references', () {
    test('keep a local root for zone resolution while serializing as ref', () {
      final engine = SessionRecorderEngine(const SessionRecorderConfig());
      final context = engine.context as ContextImpl;
      final root = Root(
        id: 1,
        objectId: 'object-1',
        widgetType: 'Button',
        renderType: 'RenderBox',
        box: const Rect.fromLTWH(0, 0, 10, 10),
        children: const [],
      );

      context.recordLom(
        Lom(id: 'lom-1', timestamp: 1, width: 10, height: 10, root: root),
      );
      context.recordLom(const LomRef(id: 'lom-1', timestamp: 2));

      final current = context.currentLomForTest;

      expect(current, isA<LomRef>());
      expect(current?.root, same(root));
      expect(current?.toMap(), {'ref': 'lom-1', 'ts': 2});
    });
  });

  group('ActionEvent payloads', () {
    test('serializes tap, double tap, and long press', () {
      expect(_tap().concatenateString(), '1:tap:z1:0,0:2,3');

      expect(
        const DoubleTapActionEvent(
          timestampRelative: 2,
          zone: 'z2',
          viewport: Rect.fromLTWH(10, 20, 100, 200),
          position: Offset(4, 5),
        ).concatenateString(),
        '2:doubleTap:z2:10,20:4,5',
      );

      expect(
        const LongPressActionEvent(
          timestampRelative: 3,
          zone: 'z3',
          viewport: Rect.fromLTWH(1, 2, 100, 200),
          position: Offset(9, 10),
          duration: Duration(milliseconds: 450),
        ).concatenateString(),
        '3:longPress:z3:1,2:9,10:450',
      );
    });
  });

  group('ExplorationEvent payloads', () {
    test('serializes drag, pinch, scroll start, and scroll end', () {
      expect(_drag().concatenateString(), '10:drag:7:0,100:20,180');

      expect(
        const PinchExplorationEvent(
          timestamp: 20,
          pointer: 2,
          viewport: Rect.fromLTWH(0, 0, 320, 640),
          endTimestamp: 80,
          positions: [Offset(10, 10), Offset(20, 20)],
        ).concatenateString(),
        '20:pinch:2:0,0:10,10|20,20:80',
      );

      expect(
        const ScrollExplorationEvent(
          timestamp: 100,
          viewport: Rect.fromLTWH(0, 100, 320, 640),
          phase: ScrollPhase.start,
        ).concatenateString(),
        '100:scrollStart:0,100,320,640',
      );

      expect(
        const ScrollExplorationEvent(
          timestamp: 200,
          viewport: Rect.fromLTWH(0, 100, 320, 640),
          phase: ScrollPhase.end,
        ).concatenateString(),
        '200:scrollEnd:0,100,320,640',
      );
    });
  });
}

/// Creates a config that allows reporter sends in debug tests.
SessionRecorderConfig _sendConfig(String endpoint) =>
    SessionRecorderConfig(endpoint: endpoint, debugSendSession: true);

/// Builds a small non-empty chunk for reporter tests.
Chunk _chunk() {
  final chunk = Chunk()..sId = 'session-id';
  chunk.addActionEvent(_tap());
  return chunk;
}

/// Shared tap fixture for action and chunk tests.
TapActionEvent _tap() {
  return const TapActionEvent(
    timestampRelative: 1,
    zone: 'z1',
    viewport: Rect.zero,
    position: Offset(2, 3),
  );
}

/// Shared drag fixture for exploration and chunk tests.
DragExplorationEvent _drag() {
  return const DragExplorationEvent(
    timestamp: 10,
    pointer: 7,
    viewport: Rect.fromLTWH(0, 100, 320, 640),
    position: Offset(20, 180),
  );
}

/// Small HTTP server used by reporter tests.
class _TestServer {
  final HttpServer _server;
  final Future<void> Function(HttpRequest request) _handler;
  int requestCount = 0;

  _TestServer._(this._server, this._handler) {
    _server.listen((request) async {
      requestCount += 1;
      await _handler(request);
    });
  }

  String get endpoint =>
      'http://${_server.address.address}:${_server.port}/endpoint';

  static Future<_TestServer> start(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _TestServer._(server, handler);
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}

/// Minimal engine stub for reporter tests.
class _FakeEngine implements SessionRecorderEngineInternal {
  _FakeEngine({required this.config, required this.context});

  @override
  final SessionRecorderConfig config;

  @override
  final _FakeContext context;

  @override
  final SessionRecorderController controller = _FakeController();

  @override
  bool get isEnabled => true;

  @override
  void start() {}
}

/// Minimal controller stub for reporter tests.
class _FakeController implements SessionRecorderController {
  @override
  bool get isNavigationAttached => false;

  @override
  void interrupt() {}

  @override
  void onInterrupt(VoidCallback? onInterrupt) {}

  @override
  void pingInactivity() {}

  @override
  void registerObserver(SessionNavigatorObserver observer) {}

  @override
  void startReporting() {}

  @override
  void stopReporting() {}
}

/// Minimal context stub with controlled chunk extraction.
class _FakeContext implements SessionRecorderContext {
  _FakeContext(this._chunks);

  final List<Chunk?> _chunks;
  int extractCount = 0;

  @override
  Chunk? extractChunk() {
    extractCount += 1;
    if (_chunks.isEmpty) return null;
    return _chunks.removeAt(0);
  }

  @override
  Element? get currentRouteElement => null;

  @override
  ValueListenable<LomAbstract?>? get notifier => null;

  @override
  Rect get screenViewport => Rect.zero;

  @override
  Rect get scrollPhysicalBounds => Rect.zero;

  @override
  Rect get scrollVirtualCanvas => Rect.zero;

  @override
  void captureTree(bool comesFromNavigation) {}

  @override
  Root? findRoot(Offset position) => null;

  @override
  void recordAction(ActionEvent action) {}

  @override
  void recordExploration(ExplorationEvent exploration) {}

  @override
  void recordLom(LomAbstract? lom) {}

  @override
  Rect resolveViewport(Offset position) => Rect.zero;

  @override
  void setCurrentRouteElement(Element? element) {}

  @override
  void setCurrentlyNavigating() {}

  @override
  void setScreenViewport(Rect sV) {}

  @override
  void setScrollPhysicalBounds(Rect sPB) {}

  @override
  void setScrollVirtualCanvas(Rect sVC) {}

  @override
  void start() {}
}
