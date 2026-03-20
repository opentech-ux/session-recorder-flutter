import 'dart:async';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:meta/meta.dart';

import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
import 'package:session_recorder_flutter/src/session/session_controller_internal.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';
import 'package:session_recorder_flutter/src/tree/tap_tree_resolver.dart';
import 'package:session_recorder_flutter/src/tree/tree_detector.dart';
import 'package:session_recorder_flutter/src/utils/session_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC FACADE
// Only configure() and init() are exposed to end users.
// ─────────────────────────────────────────────────────────────────────────────

/// {@template session_record_service}
/// Main tracker coordinator for session interaction recording and tree capture.
///
/// This class is the primary entry point of the package and the only object
/// consumers are intended to call `[init()]` and `[configure()]` method from
/// `[main()]`.
///
/// {@template session_record}
/// ### Example usage
/// ```dart
/// void main() {
///   // Important to add it before calling init method
///   WidgetsFlutterBinding.ensureInitialized();
///
///   final config = SessionRecorderConfig(
///     endpoint: 'https://api.example.com/endpoint',
///     debugLog: true,
///   );
///
///   SessionRecorder.instance.configure(config);
///   SessionRecorder.instance.init();
///
///   runApp(MyApp());
/// }
/// ```
///
/// Or also could be as :
/// ```dart
/// void main() {
///   // Important to add it before calling init method
///   WidgetsFlutterBinding.ensureInitialized();
///
///   SessionRecorder.instance
///     ..configure(
///       SessionRecorderConfig(
///         endpoint: 'https://api.example.com/endpoint',
///         debugLog: true,
///       ),
///     )
///     ..init();
///
///   runApp(MyApp());
/// }
/// ```
///
/// There is **no need to wrap it inside**
/// `[WidgetsBinding.instance.addPostFrameCallback()]`, since `[init()]`
///    already ensures the call is deferred until the first frame is rendered.
/// {@endtemplate}
///
/// This method performs several heavy operations.
/// Therefore, it **must not be called from any widget build method,
/// hot path, or frequent callback**, doing so may cause UI freezes
/// or dropped frames.
///
/// Call `[init()]` **only once**, and **only after** the app’s root widget
/// (`MaterialApp`, `CupertinoApp`, etc.) has been fully mounted.
///
/// {@endtemplate}
@sealed
class SessionRecorder {
  ///{@macro session_record_service}
  SessionRecorder._() {
    _recorder = _RecorderImpl(this);
    _controller = _ControllerImpl(this);
    _currentChunk = Chunk();
    _currentChunk.sId = _currentSession.id;
  }
  static final SessionRecorder instance = SessionRecorder._();

  late final _RecorderImpl _recorder;
  late final _ControllerImpl _controller;

  @internal
  SessionRecorderInternal get recorder => _recorder;
  @internal
  SessionControllerInternal get controller => _controller;

  late SessionRecorderConfig _config = const SessionRecorderConfig();

  @internal
  SessionRecorderConfig get config => _config;

  late Session _currentSession = Session();
  late Chunk _currentChunk;
  late LomAbstract _currentLom;
  late Rect _viewport = Rect.zero;

  Element? _currentRouteElement;

  @internal
  final ValueNotifier<List<Rect>> rects = ValueNotifier<List<Rect>>([]);

  InactivityDetector? _inactivity;
  TreeDetector? _detector;

  /// Configures the Session Recorder with the given `[SessionRecorderConfig]`
  ///
  /// Throws `[FormatException]` if the given `endpoint` from `[SessionRecorderConfig]`
  /// is not correct.
  void configure(SessionRecorderConfig config) {
    // TODO uncomment this :
    // if (!endpointRegExp.hasMatch(config.endpoint)) {
    //   throw FormatException(
    //     'Invalid Endpoint. The expected format is `https://[subdomain].ux-key.com/endpoint`, where the subdomain may only contain letters, numbers, and hyphens.',
    //   );
    // }

    _config = config;
  }

  /// Initializes the session record.
  ///
  /// This method performs the initial setup required for the widget-tree
  /// capture service:
  ///
  ///  - Ensure to call it from application startup in `[main()]`.
  ///  - Write `[WidgetsFlutterBinding.ensureInitialized();]` before this method.
  ///  - The scheduled listeners run after frames; avoid calling `[init()]` during
  ///  an unstable `[build()]`.
  ///  - Only set it **once**.
  ///
  /// {@macro session_record}
  ///
  /// See also
  ///  - `[SessionRecorderConfig]`: More information on what can be shared.
  ///
  /// Throws `[ArgumentError]` if `[SessionRecorderConfig]` are invalid.
  void init() {
    if (_detector?.isRunning == true) return;

    _detector = TreeDetector(recorder: _recorder);
    _detector!.detect();

    _controller.startReporting();
    SessionLogger.mlog("> [ SESSION RECORDER INITIALIZED ]");
  }
}

class _RecorderImpl implements SessionRecorderInternal {
  final SessionRecorder _recorder;
  _RecorderImpl(this._recorder);

  final TapTreeFinder _finder = const TapTreeFinder();

  @override
  Rect get viewport => _recorder._viewport;

  @override
  void setViewport(Rect viewport) {
    debugPrint("viewport: $viewport");
    _recorder._viewport = viewport;
  }

  @override
  Element? get currentRouteElement => _recorder._currentRouteElement;

  @override
  void recordAction(ActionEvent action) {
    _recorder._currentChunk.addActionEvent(action);
    _recorder._controller.inactivity.ping();
  }

  @override
  void recordExploration(ExplorationEvent exploration) {
    _recorder._currentChunk.addExplorationEvent(exploration);
    _recorder._controller.inactivity.ping();
  }

  @override
  void recordLom(LomAbstract lom) {
    _recorder._currentLom = lom;
    debugPrint("_currentLom.toString()");
    debugPrint(_recorder._currentLom.toString());
    _recorder._currentChunk.addLom(lom);
    debugPrint(_recorder._currentChunk.loms.length.toString());

    SessionLogger.mlog("> [ LOM SAVED - ${lom.id} sign=${lom.signature}]");
  }

  @override
  Root? findRoot(Offset position) {
    final tapTreeResult = _finder.find(_recorder._currentLom, position);
    return tapTreeResult.didTap ? tapTreeResult.target : null;
  }
}

class _ControllerImpl implements SessionControllerInternal {
  final SessionRecorder _recorder;

  _ControllerImpl(this._recorder);

  final List<SessionNavigatorObserver> _observers = [];

  @override
  void captureCurrentNavigation() => _recorder._detector?.currentlyNavigation();

  @override
  void captureTree(bool comesFromNavigation) =>
      _recorder._detector!.captureTree(comesFromNavigation);

  @override
  Element? get currentRouteElement => _recorder._currentRouteElement;

  @override
  bool get isNavigationAttached => _observers.any((o) => o.navigator != null);

  InactivityDetector get inactivity => _recorder._inactivity ??=
      InactivityDetector(onActive: startReporting, onInactive: stopReporting);

  late final _SessionRecorderReporter reporter = _SessionRecorderReporter(
    _recorder,
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
  void setCurrentRouteElement(Element? element) =>
      _recorder._currentRouteElement = element;

  @override
  void startReporting() {
    reporter.start();
    inactivity.start();
  }

  @override
  void stopReporting() {
    reporter.stop();
    inactivity.stop();
  }
}

class _SessionRecorderReporter {
  _SessionRecorderReporter(this._recorder);

  final SessionRecorder _recorder;

  /// The active periodic `[Timer]`, or `null` if no timer is running.
  Timer? _timer;

  /// The interval used for the periodic timer ticks.
  ///
  /// __Defaults to 10 seconds__
  final Duration _interval = Duration(seconds: 10);

  final IOClient _httpClient = IOClient(
    HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true,
  );

  /// Starts the session record timer subsystem.
  void start() {
    if (_recorder._config.endpoint == '') return;
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
    final chunk = _recorder._currentChunk;
    if (_recorder._currentChunk.isChunkEmpty) return;

    _recorder._currentSession = Session();
    _recorder._currentChunk = Chunk();
    _recorder._currentChunk.sId = _recorder._currentSession.id;

    await _send(chunk);
  }

  /// Periodic callback that sends the [Chunk] to the server.
  Future<void> _send(Chunk chunk) async {
    // final List<LomAbstract> loms = chunk.loms;

    final body = chunk.toJson();

    final uri = Uri.parse(_recorder._config.endpoint);

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

      SessionLogger.mlog(">> [ Sended Data - SESSION RECORDER ]");
    } on SocketException catch (e, s) {
      SessionLogger.elog("!! Network error while sending data", e, s);
    } on TimeoutException catch (e, s) {
      SessionLogger.elog("!! Request timed out", e, s);
    } on FormatException catch (e, s) {
      SessionLogger.elog("!! Response format error", e, s);
    } on HttpException catch (e, s) {
      SessionLogger.elog("!! HTTP exception", e, s);
    } catch (e, s) {
      SessionLogger.elog("!! Unexpected error sending data", e, s);
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
// import 'dart:async';
// import 'dart:io';

// import 'package:flutter/material.dart';
// import 'package:http/io_client.dart';

// import 'package:session_recorder_flutter/src/controllers/inactivity_detector.dart';
// import 'package:session_recorder_flutter/src/models/models.dart';
// import 'package:session_recorder_flutter/src/observers/session_navigator_observer.dart';
// import 'package:session_recorder_flutter/src/session/session_controller_internal.dart';
// import 'package:session_recorder_flutter/src/session/session_recorder_config.dart';
// import 'package:session_recorder_flutter/src/session/session_recorder_internal.dart';
// import 'package:session_recorder_flutter/src/tree/tap_tree_resolver.dart';
// import 'package:session_recorder_flutter/src/tree/tree_detector.dart';
// import 'package:session_recorder_flutter/src/utils/session_logger.dart';

// /// {@template session_record_service}
// /// Main service coordinator for session recording and interaction capture.
// ///
// /// This class is the primary entry point of the package and the only object
// /// consumers are intended to call `[init()]` method from `[main]`.
// ///
// /// It extends `[WidgetsBindingObserver]` to observe app lifecycle events
// /// (pause/resume/etc.) and to manage timers and periodic uploads safely.
// ///
// /// This class centralizes all the following responsibilities:
// ///  - Acts as entry point for the package (singleton).
// ///  - Exposes `[init()]` for setup.
// ///  - Forwards pointer and scroll events to `[InteractionDelegate]`.
// ///  - Detects UI changes via signature comparison and rebuilds only when needed.
// ///  - Manages timers and lifecycle pauses/resumes safely.
// ///  - Handles periodic upload of recorded session data.
// ///
// /// {@template session_record}
// /// Example usage
// /// ```dart
// /// import 'package:flutter/material.dart';
// /// import 'package:session_recorder_flutter/session_recorder.dart';
// ///
// /// void main() {
// ///   // Important to add it before calling init method
// ///   WidgetsFlutterBinding.ensureInitialized();
// ///
// ///   final params = SessionRecorderConfig(
// ///     endpoint: 'https://api.example.com/session',
// ///   );
// ///
// ///   SessionRecorder.instance.init(params);
// ///
// ///   runApp(MyApp());
// /// }
// /// ```
// ///
// /// There is **no need to wrap it inside**
// /// `[WidgetsBinding.instance.addPostFrameCallback()]`, since `[init()]`
// ///    already ensures the call is deferred until the first frame is rendered.
// /// {@endtemplate}
// ///
// /// This method performs several heavy operations.
// /// Therefore, it **must not be called from any widget build method,
// /// hot path, or frequent callback** — doing so may cause UI freezes
// /// or dropped frames.
// ///
// /// Call `[init()]` **only once**, and **only after** the app’s root widget
// /// (`MaterialApp`, `CupertinoApp`, etc.) has been fully mounted.
// ///
// /// See also
// ///  - `[InteractionDelegate]`: chunk/layout processors, which perform the
// /// low-level traversal and gesture analysis.
// /// {@endtemplate}
// class SessionRecorder {
//   ///{@macro session_record_service}
//   SessionRecorder._() {
//     _recorder = _RecorderImpl(this);
//     _ctrlImpl = _ControllerImpl(this);
//     _currentChunk = Chunk();
//     _currentChunk.sId = _currentSession.id;
//   }
//   static final SessionRecorder instance = SessionRecorder._();

//   late final _RecorderImpl _recorder;
//   late final _ControllerImpl _ctrlImpl;

//   late final SessionRecorderInternal _internal = _SessionRecorderImpl(this);
//   SessionRecorderConfig _config = const SessionRecorderConfig();

//   ///
//   void configure(SessionRecorderConfig config) {
//     // TODO uncomment this :
//     // if (!endpointRegExp.hasMatch(config.endpoint)) {
//     //   throw FormatException(
//     //     'Invalid Endpoint. The expected format is `https://[subdomain].ux-key.com/endpoint`, where the subdomain may only contain letters, numbers, and hyphens.',
//     //   );
//     // }

//     _config = config;
//   }

//   Session _currentSession = Session();
//   late Chunk _currentChunk;
//   late Lom _currentLom;

//   late final TapTreeFinder _finder = const TapTreeFinder();
//   late final InactivityDetector _inactivity = InactivityDetector(
//     onActive: () => _reporter._start(),
//     onInactive: () => _reporter._stop(),
//   );
//   late final _SessionRecorderReporter _reporter = _SessionRecorderReporter(
//     this,
//   );

//   final List<SessionNavigatorObserver> _observers = [];
//   Element? _currentRouteElement;

//   final ValueNotifier<List<Rect>> rects = ValueNotifier<List<Rect>>([]);

//   bool get _isObserverAttached => _observers.any((o) => o.navigator != null);

//   /// Last current route used to get the top context.
//   // RouteRecorded? _currentRoute;

//   /// Stores the last generated hash of the entire widget tree if there is a
//   /// change.
//   ///
//   ///  - Used to detect changes in the widget structure.
//   ///  - If the new hash matches the previous one, no additional or heavy work
//   /// is performed.
//   ///
//   /// Example:
//   /// ```dart
//   /// if (_lastHash != newHash) {
//   ///   _lastHash = newHash;
//   ///   _doHeavyWork();
//   /// }
//   /// ```
//   // String? _lastHash;

//   /// Timer used to handle debouncing of widget tree captures.
//   ///
//   ///  - Acts as a delay mechanism **(150ms)** to avoid capturing the widget
//   /// tree on every minor change.
//   ///  - The timer resets on each detected change and only triggers once no
//   /// further updates occur within the debounce window.
//   ///  - Helps reduce redundant or heavy operations by batching changes.
//   ///
//   /// Example:
//   /// ```dart
//   /// _debounce?.cancel();
//   /// _debounce = Timer(const Duration(milliseconds: 150), () {
//   ///   _captureTree();
//   /// });
//   /// ```
//   // Timer? _debounce;

//   /// Identifier used to track widget tree capture versions.
//   ///
//   ///  - Incremented each time a new widget tree is captured.
//   ///  - Allows comparison between captures: if the stored ID does not match
//   ///    the current one, it indicates a different version and no further work
//   ///    is performed.
//   ///  - Helps prevent redundant processing of outdated captures.
//   // int _captureId = 0;

//   /// Flag indicating whether the capture service has been initialized.
//   ///
//   ///  - Defaults to `false` until the [init()] is called for the first time.
//   ///  - Prevents multiple initialization attempts; if already initialized,
//   ///    subsequent calls to [init] will perform no action.
//   ///  - Ensures the service lifecycle is handled only once.
//   ///
//   /// Example:
//   /// ```dart
//   /// if (!_serviceInitialized) {
//   ///   _serviceInitialized = true;
//   ///   _doHeavyWork();
//   /// }
//   /// ```
//   // bool _serviceInitialized = false;

//   /// Disable the session recording behavior and gestures.
//   // bool _disableRecord = false;

//   /// Indicates if we are currently capturing the Tree Widget.
//   // bool _isCapturing = false;

//   /// Counter to indicates how many times we are calling the build scheduled.
//   // int _consecutiveBuilds = 0;

//   /// Creates and returns a new [HttpClient] instance.
//   ///
//   /// This client is configured to **ignore SSL certificate validation** by
//   /// always returning [true] in [badCertificateCallback].
//   ///
//   /// Use this only for **development or testing purposes**, as it disables
//   /// certificate verification and may expose the app to security risks.
//   // final IOClient _httpClient = IOClient(
//   //   HttpClient()
//   //     ..badCertificateCallback =
//   //         (X509Certificate cert, String host, int port) => true,
//   // );

//   // // * APP LIFE CYCLE
//   // @override
//   // void didChangeAppLifecycleState(AppLifecycleState state) {
//   //   if (_disableRecord) return;

//   //   switch (state) {
//   //     case AppLifecycleState.resumed:
//   //       _inactivityTimer.onInvokeInactivityTimer();
//   //       _sessionRecorderTimer.onInvokeSessionRecorderTimer();
//   //       break;
//   //     case AppLifecycleState.inactive:
//   //     case AppLifecycleState.paused:
//   //     case AppLifecycleState.hidden:
//   //     case AppLifecycleState.detached:
//   //       _inactivityTimer.stop();
//   //       _sessionRecorderTimer.stop();

//   //       break;
//   //   }
//   // }

//   /// Initializes the session record.
//   ///
//   /// This method performs the initial setup required for the widget-tree
//   /// capture service:
//   ///
//   ///  - Safe to call from application startup (for example, from `[main()]`)
//   /// or from an initialization phase.
//   ///  - Write `[WidgetsFlutterBinding.ensureInitialized();]` before this method.
//   ///  - Make sure to call this with the same navigator key used by your app's
//   ///  `MaterialApp` / `CupertinoApp` to ensure the correct `BuildContext` is
//   ///  obtained.
//   ///  - The scheduled listeners run after frames; avoid calling `[init()]` during
//   ///  an unstable `[build()]` phase where the navigator key has not yet been attached.
//   ///
//   /// {@macro session_record}
//   ///
//   /// See also
//   ///  - `[SessionRecorderConfig]`: More information on what can be shared.
//   ///
//   /// Throws `[ArgumentError]` if `[SessionRecorderConfig]` are invalid.
//   // void init(SessionRecorderConfig config) {
//   //   if (_serviceInitialized) return;

//   //   if (config.endpoint.isEmpty) {
//   //     throw ArgumentError('Endpoint provided, but cannot be empty');
//   //   }

//   //   _initServices(config);

//   //   final BuildOwner? buildOwner = WidgetsBinding.instance.buildOwner;

//   //   if (buildOwner == null) {
//   //     _serviceInitialized = false;

//   //     WidgetsBinding.instance.addPostFrameCallback((_) => init(config));
//   //     return;
//   //   }

//   //   /// The engine calls BuildOwner.onBuildScheduled when there is pending
//   //   /// work in the tree.
//   //   final Function()? onBuildScheduled = buildOwner.onBuildScheduled;

//   //   /// Every time the widget tree changes, Flutter calls onBuildScheduled.
//   //   ///
//   //   /// We intercept it and, after the frame (addPostFrameCallback),
//   //   /// we traverse the tree.
//   //   buildOwner.onBuildScheduled = () {
//   //     onBuildScheduled?.call();

//   //     if (_inactivityTimer.isInactive) return;

//   //     _requestTreeCapture();
//   //   };
//   // }

//   // * TREE DETECTOR

//   TreeDetector? _detector;
//   bool get _isDetectorRunning => _detector?.isRunning == true;

//   /// Initializes the session record.
//   ///
//   /// This method performs the initial setup required for the widget-tree
//   /// capture service:
//   ///
//   ///  - Safe to call from application startup (for example, from `[main()]`)
//   /// or from an initialization phase.
//   ///  - Write `[WidgetsFlutterBinding.ensureInitialized();]` before this method.
//   ///  - The scheduled listeners run after frames; avoid calling `[init()]` during
//   ///  an unstable `[build()]` phase where the navigator key has not yet been attached.
//   ///
//   /// {@macro session_record}
//   ///
//   /// See also
//   ///  - `[SessionRecorderConfig]`: More information on what can be shared.
//   ///
//   /// Throws `[ArgumentError]` if `[SessionRecorderConfig]` are invalid.
//   void init() {
//     if (_isDetectorRunning) return;

//     _detector = TreeDetector(recorder: _internal);
//     _detector!.detect();

//     _reporter._start();
//     _inactivity.start();

//     SessionLogger.mlog("> [ SESSION RECORDER INITIALIZED ]");
//   }

//   void _registerObserver(SessionNavigatorObserver observer) {
//     debugPrint("register observer");
//     debugPrint(_observers.toString());
//     _observers.removeWhere((obs) => obs.isDisposed);
//     if (!_observers.contains(observer)) _observers.add(observer);
//     debugPrint(_observers.toString());
//   }

//   void _captureTree(bool comesFromNavigation) =>
//       _detector!.captureTree(comesFromNavigation);

//   void _recordLom(Lom lom) {
//     _currentLom = lom;
//     debugPrint("_currentLom.toString()");
//     debugPrint(_currentLom.toString());
//     _currentChunk.addLom(lom);
//     debugPrint(_currentChunk.toString());

//     SessionLogger.mlog("> [ LOM SAVED - ${lom.id} sign=${lom.signature}]");
//   }

//   void _recordAction(ActionEvent action) {
//     _currentChunk.addActionEvent(action);
//     _inactivity.ping();
//   }

//   void _recordExploration(ExplorationEvent exploration) {
//     _currentChunk.addExplorationEvent(exploration);
//     _inactivity.ping();
//   }

//   Root? _findRoot(Offset position) {
//     final tapTreeResult = _finder.find(_currentLom, position);
//     return tapTreeResult.didTap ? tapTreeResult.target : null;
//   }

//   void _currentlyNavigationCapture() => _detector?.currentlyNavigation();

//   void _startReporting() {
//     _reporter._start();
//     _inactivity.start();
//   }

//   void _stopReporting() {
//     _reporter._stop();
//     _inactivity.stop();
//   }

//   /// Initializes all services.
//   ///
//   /// This method constructs late-initialized fields and prepares
//   /// the `[InteractionDelegate]` with its required dependencies.
//   ///
//   /// Called once during setup to ensure all components are ready.
//   // void _initServices(SessionRecorderConfig config) {
//   //   // WidgetsBinding.instance.addObserver(this);

//   //   _interactionDelegate = InteractionDelegate();
//   //   _chunkDelegate = ChunkDelegate();
//   //   _lomDelegate = LomDelegate();
//   //   _sessionDelegate = SessionDelegate();
//   //   // _sessionRecorderTimer = SessionRecorderTimer();
//   //   // _inactivityTimer = InactivityTimer();

//   //   _sessionDelegate.init();
//   //   _chunkDelegate.init(_sessionDelegate.getId());

//   //   _routeTracker = RouteTracker();
//   //   _routeTracker.registerTreeHandler(_requestTreeCaptureFromRouting);
//   //   _routeTracker.registerInitSessionHandler(() => _serviceInitialized);

//   //   // * INACTIVITY TIMER
//   //   // _inactivityTimer.onInactive = () => _sessionRecorderTimer.stop();
//   //   // _inactivityTimer.onActive = () =>
//   //   //     _sessionRecorderTimer.onInvokeSessionRecorderTimer();

//   //   // _inactivityTimer.init();

//   //   // * TIMER SESSION RECORD
//   //   // _sessionRecorderTimer.onSessionRecord = () => _sendSessionRecord(config);
//   //   // _sessionRecorderTimer.init();

//   //   _serviceInitialized = true;

//   //   SessionLogger.mlog("> [ SESSION RECORDER INITIALIZED ]");
//   // }

//   /// Coordinates a Widget Tree capture according to `_debounce` and
//   /// `_captureId` semantics.
//   ///
//   /// For the initial capture (right after the first frame), `debounce` is set
//   /// to `[false]` so the capture runs immediately without waiting.
//   /// For subsequent UI updates (scroll, drawer, dialogs, etc.), `debounce` is
//   /// set to `[true]` so rapid changes are batched before performing a capture.
//   ///
//   /// Each request increments the internal capture id to distinguish versions
//   /// and ensure that only the latest snapshot is processed.
//   ///
//   /// The actual capture routine (`_captureTree`) runs when appropriate,
//   /// validating the id to ignore stale results.
//   // void _requestTreeCapture() {
//   //   if (_routeTracker.isRouting) {
//   //     _consecutiveBuilds = 0;
//   //     return;
//   //   }

//   //   _consecutiveBuilds++;

//   //   if (_consecutiveBuilds > 60 && (_debounce != null && _debounce!.isActive)) {
//   //     _debounce?.cancel();
//   //     _consecutiveBuilds = 0;

//   //     if (_routeTracker.isRouting) return;

//   //     _captureId++;

//   //     _captureTree(id: _captureId);
//   //     return;
//   //   }

//   //   _debounce?.cancel();
//   //   _debounce = Timer(Durations.short3, () {
//   //     _consecutiveBuilds = 0;

//   //     if (_routeTracker.isRouting) return;

//   //     _captureId++;

//   //     _captureTree(id: _captureId);
//   //   });
//   // }

//   /// Request and capture the Widget Tree coming from `[RouteTracker]`.
//   ///
//   /// Each request increments the internal capture id to distinguish versions
//   /// and ensure that only the latest snapshot is processed.
//   ///
//   /// The actual capture routine (`_captureTree`) runs when appropriate,
//   /// validating the id to ignore stale results.
//   // void _requestTreeCaptureFromRouting() {
//   //   _consecutiveBuilds = 0;
//   //   _debounce?.cancel();
//   //   _isCapturing = false;
//   //   _captureId++;
//   //   _captureTree(id: _captureId);
//   // }

//   /// Captures the Widget Tree rooted at the navigator key's context and triggers
//   /// further processing if the  structure has changed.
//   ///
//   /// In general terms this traverses the element subtree to produce a compact
//   /// textual capture (widget `runtimeType` and `key` when present) in
//   /// `[_processTreeSignature()]`, then offloads hashing/heavy String work to a
//   /// background isolate to avoid blocking the UI thread.
//   ///
//   /// Notes:
//   ///  - Heavy processing (hashing, long string work) runs in a background
//   /// isolate; only lightweight traversal should occur on the UI thread.
//   ///  - Always re-check the capture `id` and `_lastHash` after async work to
//   /// avoid processing stale results.
//   ///
//   /// Also validates that the provided `id` matches the current `_captureId` and
//   /// that the computed hash differs from `_lastHash`.
//   ///
//   /// When a genuine change is detected and the `id` is still valid, call
//   /// `[_createLomTree()]` function to create the first Lom class and their Root's
//   /// children.
//   ///
//   /// Parameter:
//   ///  - [id]: capture version to validate staleness (default: 0).
//   ///
//   /// Throw `FlutterError` if no navigator context is found.
//   // Future<void> _captureTree({int id = 0}) async {
//   //   if (_isCapturing) return;

//   //   _isCapturing = true;

//   //   Future<void> isCaptured() async {
//   //     try {
//   //       _currentRoute = _routeTracker.getCurrentRoute();

//   //       if (_currentRoute == null) return;

//   //       final BuildContext? context = _currentRoute!.subtreeContext;

//   //       assert(() {
//   //         if (context == null) {
//   //           throw FlutterError.fromParts(<DiagnosticsNode>[
//   //             ErrorSummary('SessionRecorder.init failed: context not found.'),
//   //             ErrorHint(
//   //               'Ensure you pass the SessionRecorderObserver to your app.',
//   //             ),
//   //             ErrorHint(
//   //               'Example:\n'
//   //               '  runApp(MaterialApp(observers: [SessionRecorderObserver()], ...));\n',
//   //             ),
//   //             ErrorHint(
//   //               'This call is blocking and will throw to surface the incorrect'
//   //               'initialization order immediately.',
//   //             ),
//   //           ]);
//   //         }

//   //         return true;
//   //       }());

//   //       if (context == null) return;

//   //       if (!context.mounted) return;

//   //       /// If a newer capture was requested while this one was running, abort
//   //       /// processing.
//   //       //if (id != _captureId) return;

//   //       final Element element = context as Element;

//   //       /// Signs the `element` Tree Widgets
//   //       final String signature = await SerializeTreeUtils.processTreeSignature(
//   //         element,
//   //       );

//   //       /// If the stable structure did not change, no additional processing is
//   //       /// performed.
//   //       if (signature == _lastHash) return;

//   //       /// If a newer capture was requested while this one was running, abort
//   //       /// processing.
//   //       //  if (id != _captureId) return;

//   //       _lastHash = signature;

//   //       _lomDelegate.clearLom();

//   //       final lom = await _lomDelegate.createLomTree(element, signature);
//   //       if (lom == null) return;

//   //       /// If a newer capture was requested while this one was running, abort
//   //       /// processing.
//   //       //  if (id != _captureId) return;

//   //       /// Captures the first current `context` viewport
//   //       if (context.mounted) {
//   //         // ignore: use_build_context_synchronously
//   //         _interactionDelegate!.captureViewportGeometry(context, null);
//   //       }

//   //       _chunkDelegate.addLom(lom);

//   //       if (_routeTracker.isRouting) _routeTracker.isRouting = false;

//   //       return;
//   //     } catch (e, s) {
//   //       SessionLogger.elog("!! >> [Some error]", e, s);

//   //       _isCapturing = false;
//   //       if (_routeTracker.isRouting) _routeTracker.isRouting = false;

//   //       return;
//   //     }
//   //   }

//   //   await isCaptured();

//   //   _isCapturing = false;
//   // }

//   /// Periodic callback that sends the pending session record to the server.
//   ///
//   /// This method is intended to be registered as a [Timer] callback (for example
//   /// via `Timer.periodic(Duration(seconds: 30), _sendSessionRecord)`).
//   ///
//   /// If there is no data available in the [Chunk], returns nothing until
//   /// `[InactivityTimer]` cancels the `[SessionRecorderTimer]`.
//   // Future<void> _sendSessionRecord(SessionRecorderConfig params) async {
//   //   if (_chunkDelegate.isChunkEmpty) return;

//   //   final chunk = _chunkDelegate.chunk;

//   //   final List<LomAbstract> lastLoms = _chunkDelegate.chunk.loms;

//   //   final body = chunk.toJson();

//   //   final uri = Uri.parse(params.endpoint!);

//   //   try {
//   //     final response = await _httpClient.post(
//   //       uri,
//   //       headers: <String, String>{
//   //         'Content-Type': 'application/json; charset=UTF-8',
//   //       },
//   //       body: body,
//   //     );

//   //     if (response.statusCode < 200 || response.statusCode >= 300) {
//   //       throw HttpException(
//   //         'Server responded with status ${response.statusCode}',
//   //         uri: uri,
//   //       );
//   //     }

//   //     SessionLogger.mlog(">> [ Sended Data - SESSION RECORDER ]");
//   //   } on SocketException catch (e, s) {
//   //     SessionLogger.elog("!! Network error while sending data", e, s);
//   //   } on TimeoutException catch (e, s) {
//   //     SessionLogger.elog("!! Request timed out", e, s);
//   //   } on FormatException catch (e, s) {
//   //     SessionLogger.elog("!! Response format error", e, s);
//   //   } on HttpException catch (e, s) {
//   //     SessionLogger.elog("!! HTTP exception", e, s);
//   //   } catch (e, s) {
//   //     SessionLogger.elog("!! Unexpected error sending data", e, s);
//   //   }

//   //   final List<LomAbstract> currentLoms = _chunkDelegate.chunk.loms;

//   //   currentLoms.removeWhere(
//   //     (lom) => lastLoms.any((lastLom) => lom.id == lastLom.id),
//   //   );

//   //   _lomDelegate.clearLom();
//   //   _chunkDelegate.init(_sessionDelegate.getId());

//   //   if (currentLoms.isNotEmpty) {
//   //     for (LomAbstract lom in currentLoms) {
//   //       _chunkDelegate.addLom(lom);
//   //     }
//   //   }
//   // }

//   // * ----- POINTER LISTENER ------ * //

//   /// Forwards the `[PointerDownEvent]` to the `[InteractionDelegate]`.
//   // void onPointerDown(PointerDownEvent e) {
//   //   if (_disableRecord || !_serviceInitialized) return;
//   //   _inactivityTimer.onInvokeInactivityTimer();
//   //   _interactionDelegate!.onPointerDown(e);
//   // }

//   // /// Forwards the `[PointerMoveEvent]` to the `[InteractionDelegate]`.
//   // void onPointerMove(PointerMoveEvent e) {
//   //   if (_disableRecord || !_serviceInitialized) return;
//   //   _inactivityTimer.onInvokeInactivityTimer();
//   //   _interactionDelegate!.onPointerMove(e);
//   // }

//   // /// Forwards the `[PointerUpEvent]` to the `[InteractionDelegate]`.
//   // void onPointerUp(PointerUpEvent e) {
//   //   if (_disableRecord || !_serviceInitialized) return;
//   //   _inactivityTimer.onInvokeInactivityTimer();
//   //   _interactionDelegate!.onPointerUp(e);
//   // }

//   // /// Forwards the `[PointerCancelEvent]` to the `[InteractionDelegate]`.
//   // void onPointerCancel(_) {
//   //   if (_disableRecord || !_serviceInitialized) return;
//   //   _inactivityTimer.onInvokeInactivityTimer();
//   //   _interactionDelegate!.onPointerCancel();
//   // }

//   // * ----- SCROLL NOTIFICATION ------ * //

//   /// Forwards the `[ScrollNotification]` to the `[InteractionDelegate]` for
//   /// processing.
//   ///
//   /// Returns `true` if the delegate handled the notification, `false` otherwise.
//   // bool handleScrollNotification(ScrollNotification s) {
//   //   if (_disableRecord || !_serviceInitialized) return false;
//   //   _inactivityTimer.onInvokeInactivityTimer();
//   //   return _interactionDelegate!.handleScrollNotification(s);
//   // }
// }

// class _ControllerImpl implements SessionControllerInternal {
//   final SessionRecorder _recorder;
//   _ControllerImpl(this._recorder);

//   @override
//   void captureCurrentNavigation() {
//     // TODO: implement captureCurrentNavigation
//   }

//   @override
//   void captureTree(bool comesFromNavigation) {
//     // TODO: implement captureTree
//   }

//   @override
//   // TODO: implement currentRouteElement
//   Element? get currentRouteElement => throw UnimplementedError();

//   @override
//   Root? findRoot(Offset position) {
//     // TODO: implement findRoot
//     throw UnimplementedError();
//   }

//   @override
//   // TODO: implement isNavigationAttached
//   bool get isNavigationAttached => throw UnimplementedError();

//   @override
//   void registerObserver(SessionNavigatorObserver observer) {
//     // TODO: implement registerObserver
//   }

//   @override
//   void setCurrentRouteElement(Element? element) {
//     // TODO: implement setCurrentRouteElement
//   }

//   @override
//   void startReporting() {
//     // TODO: implement startReporting
//   }

//   @override
//   void stopReporting() {
//     // TODO: implement stopReporting
//   }
// }

// class _RecorderImpl implements SessionRecorderInternal {
//   final SessionRecorder _recorder;
//   _RecorderImpl(this._recorder);

//   @override
//   void recordAction(ActionEvent action) {
//     // TODO: implement recordAction
//   }

//   @override
//   void recordExploration(ExplorationEvent exploration) {
//     // TODO: implement recordExploration
//   }

//   @override
//   void recordLom(Lom lom) {
//     // TODO: implement recordLom
//   }
// }

// class _SessionRecorderReporter {
//   _SessionRecorderReporter(this._recorder);

//   final SessionRecorder _recorder;

//   /// The active periodic `[Timer]`, or `null` if no timer is running.
//   Timer? _timer;

//   /// The interval used for the periodic timer ticks.
//   ///
//   /// __Defaults to 10 seconds__
//   final Duration _interval = Duration(seconds: 10);

//   final IOClient _httpClient = IOClient(
//     HttpClient()
//       ..badCertificateCallback =
//           (X509Certificate cert, String host, int port) => true,
//   );

//   /// Starts the session record timer subsystem.
//   void _start() {
//     if (_recorder._config.endpoint == '') return;
//     if (_timer?.isActive ?? false) return;

//     _timer = Timer.periodic(_interval, (_) => _flush());
//   }

//   /// Stops the periodic timer and clears its reference.
//   void _stop() {
//     if (_timer == null) return;

//     _timer?.cancel();
//     _timer = null;
//   }

//   /// Validates the [Chunk] before to send it into the server
//   Future<void> _flush() async {
//     final chunk = _recorder._currentChunk;
//     if (_recorder._currentChunk.isChunkEmpty) return;

//     _recorder._currentSession = Session();
//     _recorder._currentChunk = Chunk();
//     _recorder._currentChunk.sId = _recorder._currentSession.id;

//     await _send(chunk);
//   }

//   /// Periodic callback that sends the [Chunk] to the server.
//   Future<void> _send(Chunk chunk) async {
//     // final List<LomAbstract> loms = chunk.loms;

//     final body = chunk.toJson();

//     final uri = Uri.parse(_recorder._config.endpoint);

//     try {
//       final response = await _httpClient.post(
//         uri,
//         headers: <String, String>{
//           'Content-Type': 'application/json; charset=UTF-8',
//         },
//         body: body,
//       );

//       if (response.statusCode < 200 || response.statusCode >= 300) {
//         throw HttpException(
//           'Server responded with status ${response.statusCode}',
//           uri: uri,
//         );
//       }

//       SessionLogger.mlog(">> [ Sended Data - SESSION RECORDER ]");
//     } on SocketException catch (e, s) {
//       SessionLogger.elog("!! Network error while sending data", e, s);
//     } on TimeoutException catch (e, s) {
//       SessionLogger.elog("!! Request timed out", e, s);
//     } on FormatException catch (e, s) {
//       SessionLogger.elog("!! Response format error", e, s);
//     } on HttpException catch (e, s) {
//       SessionLogger.elog("!! HTTP exception", e, s);
//     } catch (e, s) {
//       SessionLogger.elog("!! Unexpected error sending data", e, s);
//     }

//     // final List<LomAbstract> currentLoms = chunk.loms;

//     // currentLoms.removeWhere(
//     //   (lom) => lastLoms.any((lastLom) => lom.id == lastLom.id),
//     // );

//     // _lomDelegate.clearLom();
//     // _chunkDelegate.init(_sessionDelegate.getId());

//     // if (currentLoms.isNotEmpty) {
//     //   for (LomAbstract lom in currentLoms) {
//     //     _chunkDelegate.addLom(lom);
//     //   }
//     // }
//   }
// }
