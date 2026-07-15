import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_recorder_flutter/src/collectors/gestures_collector.dart';
import 'package:session_recorder_flutter/src/collectors/scroll_collector.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_context.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_controller.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_engine.dart';
import 'package:session_recorder_flutter/src/core/session_recorder_reporter.dart';
import 'package:session_recorder_flutter/src/enums/gestures_type_enum.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/session/session_logger.dart';
import 'package:session_recorder_flutter/src/tree/lom_tree_inspector.dart';

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

  group('Navigation capture', () {
    test('coalesces nested navigator transitions into one capture', () {
      final engine = _FakeEngine.empty();
      final controller = ControllerImpl(engine);
      var interrupts = 0;
      controller.onInterrupt(() => interrupts++);

      controller.beginNavigation();
      controller.beginNavigation();
      controller.finishNavigation(null);

      expect(engine.context.navigationCaptureCount, 0);

      controller.finishNavigation(null);

      expect(interrupts, 1);
      expect(engine.context.navigatingCount, 1);
      expect(engine.context.navigationCaptureCount, 1);
    });
  });

  group('LOM references', () {
    test('tracks the current LOM ref without adding local refs to chunks', () {
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
      context.recordLom(LocalLomRef(id: 'lom-1', timestamp: 2, root: root));

      final current = context.currentLomForTest;

      expect(current, isA<LomRef>());
      expect(context.currentLomRef, 'lom-1');
      expect(current?.toMap(), {'ref': 'lom-1', 'ts': 2});
    });

    test('measures the complete materialized tree extent', () {
      const root = Root(
        id: 1,
        objectId: 'root',
        widgetType: 'Screen',
        renderType: 'RenderBox',
        box: Rect.fromLTWH(0, 0, 390, 720),
        children: [
          Root(
            id: 2,
            objectId: 'off-screen',
            widgetType: 'Card',
            renderType: 'RenderBox',
            box: Rect.fromLTWH(12, 1800, 366, 80),
            children: [],
          ),
        ],
      );

      expect(
        LomTreeInspector.materializedContentSize(root),
        const Size(390, 1880),
      );
    });

    test('serializes the optional viewport anchor in LOM records', () {
      const viewport = Offset(12.4, 1159.6);
      final lomMap = const Lom(
        id: 'lom-full',
        timestamp: 2,
        width: 390,
        height: 2200,
        viewportOffset: viewport,
      ).toMap();

      expect(lomMap['v'], [12, 1160]);

      expect(
        const LomRef(
          id: 'lom-viewport',
          timestamp: 3,
          viewportOffset: viewport,
        ).toMap(),
        {
          'ref': 'lom-viewport',
          'ts': 3,
          'v': [12, 1160],
        },
      );

      expect(
        const Root(
          id: 1,
          objectId: 'fixed',
          widgetType: 'IconButton',
          renderType: 'RenderBox',
          box: Rect.fromLTWH(0, 0, 40, 40),
          children: [],
          coordinateSpace: LomCoordinateSpace.screen,
        ).toMap()['s'],
        's',
      );
    });

    testWidgets('keeps an eager scroll tree stable across offsets', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const captureKey = Key('capture-root');
      const scrollKey = Key('eager-scroll');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            key: captureKey,
            width: 300,
            height: 240,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    key: scrollKey,
                    controller: controller,
                    child: const Column(
                      children: [
                        SizedBox(height: 300, child: Text('top')),
                        SizedBox(height: 300, child: Text('middle')),
                        SizedBox(height: 300, child: Text('bottom')),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {},
                    child: const SizedBox(width: 40, height: 40),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final inspector = LomTreeInspector();
      final captureElement = tester.element(find.byKey(captureKey));
      final initial = inspector.captureLom(
        captureElement,
        comesFromNavigation: false,
      );

      controller.jumpTo(420);
      await tester.pump();

      final scrolled = inspector.captureLom(
        captureElement,
        comesFromNavigation: false,
      );

      expect(initial, isA<Lom>());
      expect(initial?.viewportOffset, Offset.zero);
      final initialRoot = initial?.root;
      expect(initialRoot?.coordinateSpace, LomCoordinateSpace.mixed);

      Iterable<Root> flatten(Root node) sync* {
        yield node;
        for (final child in node.children) {
          yield* flatten(child);
        }
      }

      final initialNodes = flatten(initialRoot!).toList();
      expect(
        initialNodes.any(
          (node) =>
              node.widgetType == 'GestureDetector' &&
              node.coordinateSpace == LomCoordinateSpace.screen,
        ),
        isTrue,
      );
      expect(
        initialNodes.any(
          (node) => node.coordinateSpace == LomCoordinateSpace.content,
        ),
        isTrue,
      );
      expect(scrolled, isA<LomRef>());
      expect(scrolled?.id, initial?.id);
      expect(scrolled?.viewportOffset, const Offset(0, 420));
    });

    testWidgets('does not promote a small carousel to route viewport', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const captureKey = Key('carousel-only-root');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            key: captureKey,
            width: 300,
            height: 240,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 80,
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 800, height: 80),
                ),
              ),
            ),
          ),
        ),
      );

      controller.jumpTo(200);
      await tester.pump();

      final lom = LomTreeInspector().captureLom(
        tester.element(find.byKey(captureKey)),
        comesFromNavigation: false,
      );

      expect(lom?.viewportOffset, Offset.zero);
    });

    testWidgets('keeps a nested carousel offset local', (tester) async {
      final verticalController = ScrollController();
      final horizontalController = ScrollController();
      addTearDown(verticalController.dispose);
      addTearDown(horizontalController.dispose);
      const captureKey = Key('nested-capture-root');
      const cardKey = Key('nested-card');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            key: captureKey,
            width: 300,
            height: 240,
            child: SingleChildScrollView(
              controller: verticalController,
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: SingleChildScrollView(
                      controller: horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 800,
                        height: 100,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 240,
                              child: GestureDetector(
                                key: cardKey,
                                onTap: () {},
                                child: const SizedBox(width: 80, height: 80),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      );

      Iterable<Root> flatten(Root node) sync* {
        yield node;
        for (final child in node.children) {
          yield* flatten(child);
        }
      }

      final inspector = LomTreeInspector();
      final captureElement = tester.element(find.byKey(captureKey));
      final cardObjectId = tester
          .element(find.byKey(cardKey))
          .renderObject
          .hashCode
          .toRadixString(16);
      final initial = inspector.captureLom(
        captureElement,
        comesFromNavigation: false,
      );
      final initialCard = flatten(
        initial!.root!,
      ).firstWhere((node) => node.objectId == cardObjectId);

      verticalController.jumpTo(200);
      horizontalController.jumpTo(120);
      await tester.pump();

      final scrolled = inspector.captureLom(
        captureElement,
        comesFromNavigation: false,
      );
      final scrolledCard = flatten(
        scrolled!.root!,
      ).firstWhere((node) => node.objectId == cardObjectId);

      expect(scrolled.viewportOffset, const Offset(0, 200));
      expect(scrolledCard.box.left, initialCard.box.left - 120);
      expect(scrolledCard.box.top, initialCard.box.top);
    });

    testWidgets('keeps TabBarView page offsets local', (tester) async {
      const captureKey = Key('tab-capture-root');
      const activeKey = Key('active-tab-content');

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              key: captureKey,
              width: 300,
              height: 240,
              child: DefaultTabController(
                length: 3,
                initialIndex: 2,
                child: TabBarView(
                  children: [
                    const SizedBox(),
                    const SizedBox(),
                    Center(
                      child: ElevatedButton(
                        key: activeKey,
                        onPressed: null,
                        child: const Text('active'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final activeObjectId = tester
          .element(find.byKey(activeKey))
          .renderObject
          .hashCode
          .toRadixString(16);
      final lom = LomTreeInspector().captureLom(
        tester.element(find.byKey(captureKey)),
        comesFromNavigation: false,
      );

      Iterable<Root> flatten(Root node) sync* {
        yield node;
        for (final child in node.children) {
          yield* flatten(child);
        }
      }

      expect(lom?.viewportOffset, Offset.zero);
      expect(
        flatten(lom!.root!).any((node) => node.objectId == activeObjectId),
        isTrue,
      );
    });

    testWidgets('skips hidden Offstage branches', (tester) async {
      const captureKey = Key('offstage-capture-root');
      const hiddenKey = Key('hidden-offstage-content');
      const visibleKey = Key('visible-offstage-content');

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            key: captureKey,
            width: 300,
            height: 240,
            child: Stack(
              children: [
                Offstage(
                  offstage: true,
                  child: ElevatedButton(
                    key: hiddenKey,
                    onPressed: null,
                    child: const Text('hidden'),
                  ),
                ),
                Offstage(
                  child: ElevatedButton(
                    key: visibleKey,
                    onPressed: null,
                    child: const Text('visible'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      String objectId(Key key) => tester
          .element(find.byKey(key))
          .renderObject
          .hashCode
          .toRadixString(16);
      final lom = LomTreeInspector().captureLom(
        tester.element(find.byKey(captureKey)),
        comesFromNavigation: false,
      );

      Iterable<Root> flatten(Root node) sync* {
        yield node;
        for (final child in node.children) {
          yield* flatten(child);
        }
      }

      final ids = flatten(lom!.root!).map((node) => node.objectId).toSet();
      expect(ids, contains(objectId(visibleKey)));
      expect(ids, isNot(contains(objectId(hiddenKey))));
    });

    test('maps viewport pixels back into content coordinates', () {
      expect(
        LomTreeInspector.viewportContentOffset(AxisDirection.down, 120),
        const Offset(0, 120),
      );
      expect(
        LomTreeInspector.viewportContentOffset(AxisDirection.up, 120),
        const Offset(0, -120),
      );
      expect(
        LomTreeInspector.viewportContentOffset(AxisDirection.right, 120),
        const Offset(120, 0),
      );
      expect(
        LomTreeInspector.viewportContentOffset(AxisDirection.left, 120),
        const Offset(-120, 0),
      );
    });
  });

  group('ActionEvent payloads', () {
    test('serializes tap, double tap, and long press', () {
      expect(_tap().concatenateString(), '1:tap:0,0:2,3:lom-1');

      expect(
        const DoubleTapActionEvent(
          timestampRelative: 2,
          viewport: Rect.fromLTWH(10, 20, 100, 200),
          position: Offset(4, 5),
          lomRef: 'lom-2',
        ).concatenateString(),
        '2:doubleTap:10,20:4,5:lom-2',
      );

      expect(
        const LongPressActionEvent(
          timestampRelative: 3,
          viewport: Rect.fromLTWH(1, 2, 100, 200),
          position: Offset(9, 10),
          lomRef: 'lom-3',
          duration: Duration(milliseconds: 450),
        ).concatenateString(),
        '3:longPress:1,2:9,10:450:lom-3',
      );
    });
  });

  group('ScrollCollector', () {
    testWidgets('captures the active TabBarView page after it settles', (
      tester,
    ) async {
      final context = _FakeContext([]);
      final collector = ScrollCollector(
        engine: _FakeEngine(
          config: const SessionRecorderConfig(),
          context: context,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'First'),
                    Tab(key: Key('second-tab'), text: 'Second'),
                  ],
                ),
              ),
              body: NotificationListener<ScrollNotification>(
                onNotification: collector.handleScrollNotification,
                child: const TabBarView(
                  children: [Text('first page'), Text('second page')],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('second-tab')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump();

      expect(context.uiCaptureCount, 1);
    });
  });

  group('GestureCollector', () {
    test('keeps multi-touch double taps grouped with their origin tap', () {
      final context = _FakeContext([]);
      final collector = GestureCollector(
        engine: _FakeEngine(
          config: const SessionRecorderConfig(),
          context: context,
        ),
      );

      collector.onPointerDown(
        const PointerDownEvent(pointer: 1, position: Offset(10, 10)),
      );
      collector.onPointerUp(
        const PointerUpEvent(pointer: 1, position: Offset(10, 10)),
      );

      collector.onPointerDown(
        const PointerDownEvent(pointer: 2, position: Offset(30, 30)),
      );
      collector.onPointerUp(
        const PointerUpEvent(pointer: 2, position: Offset(30, 30)),
      );

      expect(context.actionsEvents.map((event) => event.actionType), [
        GesturesType.tap,
        GesturesType.tap,
      ]);

      collector.onPointerDown(
        const PointerDownEvent(pointer: 3, position: Offset(11, 11)),
      );
      collector.onPointerUp(
        const PointerUpEvent(pointer: 3, position: Offset(11, 11)),
      );

      collector.onPointerDown(
        const PointerDownEvent(pointer: 4, position: Offset(31, 31)),
      );
      collector.onPointerUp(
        const PointerUpEvent(pointer: 4, position: Offset(31, 31)),
      );

      expect(context.actionsEvents.map((event) => event.actionType), [
        GesturesType.tap,
        GesturesType.doubleTap,
        GesturesType.tap,
        GesturesType.doubleTap,
      ]);
    });

    test('does not duplicate the last sampled point', () {
      final collector = GestureCollector(engine: _FakeEngine.empty());
      final positions = [
        TimedPosition(Offset.zero, viewport: Rect.zero),
        TimedPosition(const Offset(1, 1), viewport: Rect.zero),
        TimedPosition(const Offset(2, 2), viewport: Rect.zero),
      ];

      final sampled = collector.samplePositionsForTest(
        positions,
        timestampThresholdMs: 0,
      );

      expect(sampled, hasLength(3));
      expect(sampled.last, same(positions.last));
    });
  });

  group('ExplorationEvent payloads', () {
    test('serializes drag, pinch, scroll start, and scroll end', () {
      expect(_drag().concatenateString(), '10:drag:7:0,100:20,180:lom-1');

      expect(
        const PinchExplorationEvent(
          timestamp: 20,
          pointer: 2,
          viewport: Rect.fromLTWH(0, 0, 320, 640),
          endTimestamp: 80,
          positions: [Offset(10, 10), Offset(20, 20)],
          lomRef: 'lom-2',
        ).concatenateString(),
        '20:pinch:2:0,0:10,10|20,20:80:lom-2',
      );

      expect(
        const ScrollExplorationEvent(
          timestamp: 100,
          viewport: Rect.fromLTWH(0, 100, 320, 640),
          offset: Offset.zero,
          phase: ScrollPhase.start,
          lomRef: 'lom-3',
        ).concatenateString(),
        '100:scrollStart:0,100,320,640:0,0:lom-3',
      );

      expect(
        const ScrollExplorationEvent(
          timestamp: 200,
          viewport: Rect.fromLTWH(0, 100, 320, 640),
          offset: Offset(0, 480),
          phase: ScrollPhase.end,
          lomRef: 'lom-3',
        ).concatenateString(),
        '200:scrollEnd:0,100,320,640:0,480:lom-3',
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
    viewport: Rect.zero,
    position: Offset(2, 3),
    lomRef: 'lom-1',
  );
}

/// Shared drag fixture for exploration and chunk tests.
DragExplorationEvent _drag() {
  return const DragExplorationEvent(
    timestamp: 10,
    pointer: 7,
    viewport: Rect.fromLTWH(0, 100, 320, 640),
    position: Offset(20, 180),
    lomRef: 'lom-1',
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

  factory _FakeEngine.empty() {
    return _FakeEngine(
      config: const SessionRecorderConfig(),
      context: _FakeContext([]),
    );
  }

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
  void beginNavigation() {}

  @override
  void finishNavigation(Element? routeElement) {}

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

  @override
  void dispose() {}
}

/// Minimal context stub with controlled chunk extraction.
class _FakeContext implements SessionRecorderContext {
  _FakeContext(this._chunks);

  final List<Chunk?> _chunks;
  final Chunk _actionsChunk = Chunk();
  final List<ActionEvent> actionsEvents = [];
  final List<ExplorationEvent> explorationEvents = [];
  int extractCount = 0;
  int navigatingCount = 0;
  int navigationCaptureCount = 0;
  int uiCaptureCount = 0;

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
  void captureTree(bool comesFromNavigation) {
    if (comesFromNavigation) {
      navigationCaptureCount++;
    } else {
      uiCaptureCount++;
    }
  }

  @override
  void dispose() {}

  @override
  String? get currentLomRef => 'lom-1';

  @override
  void recordAction(ActionEvent action) {
    _actionsChunk.addActionEvent(action);
    actionsEvents
      ..clear()
      ..addAll(_actionsChunk.actionsEvents);
  }

  @override
  void recordExploration(ExplorationEvent exploration) {
    explorationEvents.add(exploration);
  }

  @override
  void recordLom(LomAbstract? lom) {}

  @override
  Rect resolveViewport(Offset position) => Rect.zero;

  @override
  void setCurrentRouteElement(Element? element) {}

  @override
  void setCurrentlyNavigating() => navigatingCount++;

  @override
  void setCurrentlyScrolling(bool isScrolling) {}

  @override
  void setScreenViewport(Rect sV) {}

  @override
  void setScrollPhysicalBounds(Rect sPB) {}

  @override
  void start() {}
}
