import 'dart:async' show Timer, TimeoutException;
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:http/io_client.dart';

import 'package:session_recorder_flutter/src/delegates/chunk_delegate.dart';
import 'package:session_recorder_flutter/src/delegates/interaction_delegate.dart';
import 'package:session_recorder_flutter/src/delegates/layout_object_manager_delegate.dart';
import 'package:session_recorder_flutter/src/delegates/session_delegate.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/services/route_tracker.dart';
import 'package:session_recorder_flutter/src/services/timers/inactivity_timer.dart';
import 'package:session_recorder_flutter/src/services/timers/session_recorder_timer.dart';
import 'package:session_recorder_flutter/src/utils/serialize_tree_utils.dart';

/// Main service coordinator for session recording and interaction capture.
///
/// This class is the primary entry point of the package and the only object
/// consumers are intended to call [init()] method from [main].
///
/// It extends [WidgetsBindingObserver] to observe app lifecycle events
/// (pause/resume/etc.) and to manage timers and periodic uploads safely.
///
/// This class centralizes all the following responsibilities:
///  - Acts as entry point for the package (singleton).
///  - Exposes [init()] for setup.
///  - Forwards pointer and scroll events to [InteractionDelegate].
///  - Detects UI changes via signature comparison and rebuilds only when needed.
///  - Manages timers and lifecycle pauses/resumes safely.
///  - Handles periodic upload of recorded session data.
///
/// {@template session_record}
/// Example usage
/// ```dart
/// final navigatorKey = GlobalKey<NavigatorState>();
/// void main() {
///   // Important to add it before calling init method
///   WidgetsFlutterBinding.ensureInitialized();
///
///   final params = SessionRecorderParams(
///     key: navigatorKey,
///     endpoint: 'https://api.example.com/session',
///   );
///
///   SessionRecorder.instance.init(params);
///
///   runApp(MyApp(navigatorKey: navigatorKey));
/// }
/// ```
///
/// There is **no need to wrap it inside**
/// [WidgetsBinding.instance.addPostFrameCallback()], since `[init()]`
///    already ensures the call is deferred until the first frame is rendered.
/// {@endtemplate}
///
/// This method performs several heavy operations.
/// Therefore, it **must not be called from any widget build method,
/// hot path, or frequent callback** — doing so may cause UI freezes
/// or dropped frames.
///
/// Call [init()] **only once**, and **only after** the app’s root widget
/// (`MaterialApp`, `CupertinoApp`, etc.) has been fully mounted.
///
/// See also
///  - [InteractionDelegate], chunk/layout processors, which perform the
/// low-level traversal and gesture analysis.
class SessionRecorder extends WidgetsBindingObserver {
  SessionRecorder._internal();
  static final SessionRecorder instance = SessionRecorder._internal();
  factory SessionRecorder() => instance;

  // * DELEGATES
  late final ChunkDelegate _chunkDelegate;
  late final LomDelegate _lomDelegate;
  late final SessionDelegate _sessionDelegate;
  late final SessionRecorderTimer _sessionRecorderTimer;
  late final InactivityTimer _inactivityTimer;
  late final RouteTracker _routeTracker;
  InteractionDelegate? _interactionDelegate;

  final ValueNotifier<List<Rect>> rects = ValueNotifier<List<Rect>>([]);

  ///
  RouteRecorded? _currentRoute;

  /// Stores the last generated hash of the entire widget tree if there is a
  /// change.
  ///
  ///  - Used to detect changes in the widget structure.
  ///  - If the new hash matches the previous one, no additional or heavy work
  /// is performed.
  ///
  /// Example:
  /// ```dart
  /// if (_lastHash != newHash) {
  ///   _lastHash = newHash;
  ///   _doHeavyWork();
  /// }
  /// ```
  String? _lastHash;

  /// Timer used to handle debouncing of widget tree captures.
  ///
  ///  - Acts as a delay mechanism **(150ms)** to avoid capturing the widget
  /// tree on every minor change.
  ///  - The timer resets on each detected change and only triggers once no
  /// further updates occur within the debounce window.
  ///  - Helps reduce redundant or heavy operations by batching changes.
  ///
  /// Example:
  /// ```dart
  /// _debounce?.cancel();
  /// _debounce = Timer(const Duration(milliseconds: 150), () {
  ///   _captureTree();
  /// });
  /// ```
  Timer? _debounce;

  /// Identifier used to track widget tree capture versions.
  ///
  ///  - Incremented each time a new widget tree is captured.
  ///  - Allows comparison between captures: if the stored ID does not match
  ///    the current one, it indicates a different version and no further work
  ///    is performed.
  ///  - Helps prevent redundant processing of outdated captures.
  int _captureId = 0;

  /// Flag indicating whether the capture service has been initialized.
  ///
  ///  - Defaults to `false` until the [init()] is called for the first time.
  ///  - Prevents multiple initialization attempts; if already initialized,
  ///    subsequent calls to [init] will perform no action.
  ///  - Ensures the service lifecycle is handled only once.
  ///
  /// Example:
  /// ```dart
  /// if (!_serviceInitialized) {
  ///   _serviceInitialized = true;
  ///   _doHeavyWork();
  /// }
  /// ```
  bool _serviceInitialized = false;

  /// Disable the session recording behavior and gestures.
  bool _disableRecord = false;

  /// Creates and returns a new [HttpClient] instance.
  ///
  /// This client is configured to **ignore SSL certificate validation** by
  /// always returning [true] in [badCertificateCallback].
  ///
  /// Use this only for **development or testing purposes**, as it disables
  /// certificate verification and may expose the app to security risks.
  final IOClient _httpClient = IOClient(
    HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true,
  );

  // * APP LIFE CYCLE
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disableRecord) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _inactivityTimer.onInvokeInactivityTimer();
        _sessionRecorderTimer.onInvokeSessionRecorderTimer();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _inactivityTimer.stop();
        _sessionRecorderTimer.stop();

        break;
    }
  }

  /// Initializes the session record.
  ///
  /// This method performs the initial setup required for the widget-tree
  /// capture service:
  ///
  ///  - Safe to call from application startup (for example, from [main()]
  ///  after the app's `navigatorKey` is created) or from an initialization
  ///  phase.
  ///  - Write [WidgetsFlutterBinding.ensureInitialized();] before this method.
  ///  - Make sure to call this with the same navigator key used by your app's
  ///  `MaterialApp` / `CupertinoApp` to ensure the correct `BuildContext` is
  ///  obtained.
  ///  - The scheduled listeners run after frames; avoid calling [init()] during
  ///  an unstable [build()] phase where the navigator key has not yet been attached.
  ///
  /// {@macro session_record}
  ///
  /// See also
  ///  - [SessionRecorderParams] for more information on what can be shared.
  ///
  /// Throws [ArgumentError] if [SessionRecorderParams] are invalid.
  void init(SessionRecorderParams params) {
    _disableRecord = params.disable;

    if (_serviceInitialized || _disableRecord) return;

    if (params.endpoint == null) {
      throw ArgumentError.notNull(
        'The endpoint and navigator key must be provided',
      );
    }

    if (params.endpoint!.isEmpty) {
      throw ArgumentError('Endpoint provided, but cannot be empty');
    }

    _initServices(params);

    final BuildOwner? buildOwner = WidgetsBinding.instance.buildOwner;

    if (buildOwner == null) {
      _serviceInitialized = false;

      WidgetsBinding.instance.addPostFrameCallback((_) => init(params));
      return;
    }

    /// The engine calls BuildOwner.onBuildScheduled when there is pending
    /// work in the tree.
    final Function()? onBuildScheduled = buildOwner.onBuildScheduled;

    /// Every time the widget tree changes, Flutter calls onBuildScheduled.
    ///
    /// We intercept it and, after the frame (addPostFrameCallback),
    /// we traverse the tree.
    buildOwner.onBuildScheduled = () {
      onBuildScheduled?.call();

      if (_routeTracker.isObserving) return;

      _requestTreeCapture(debounce: true);
    };

    /// Request the initial tree capture
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestTreeCapture();
    });
  }

  /// Initializes all services.
  ///
  /// This method constructs late-initialized fields and prepares
  /// the [InteractionDelegate] with its required dependencies.
  ///
  /// Called once during setup to ensure all components are ready.
  void _initServices(SessionRecorderParams params) {
    WidgetsBinding.instance.addObserver(this);

    _interactionDelegate = InteractionDelegate();
    _chunkDelegate = ChunkDelegate();
    _lomDelegate = LomDelegate();
    _sessionDelegate = SessionDelegate();
    _sessionRecorderTimer = SessionRecorderTimer();
    _inactivityTimer = InactivityTimer();

    _sessionDelegate.init();
    _chunkDelegate.init(_sessionDelegate.getId());

    _routeTracker = RouteTracker();
    _routeTracker.registerTreeHandler(_requestTreeCaptureFromRouting);
    _routeTracker.registerInitSessionHandler(() => _serviceInitialized);

    // * INACTIVITY TIMER
    _inactivityTimer.onInactive = () => _sessionRecorderTimer.stop();
    _inactivityTimer.onActive = () =>
        _sessionRecorderTimer.onInvokeSessionRecorderTimer();

    _inactivityTimer.init();

    // * TIMER SESSION RECORD
    _sessionRecorderTimer.onSessionRecord = () => _sendSessionRecord(params);
    _sessionRecorderTimer.init();

    _serviceInitialized = true;

    debugPrint("> [ SESSION RECORDER INITIALIZED ]");
  }

  /// Releases all resources held by this service.
  ///
  /// This method should be called when the service is no longer needed,
  /// typically during application shutdown or when the owning widget is
  /// disposed.
  ///
  /// Once disposed, the service cannot be safely reused unless re-initialized
  /// with [init()].
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void dispose() {
  ///   SessionRecorder.instance.dispose();
  ///   super.dispose();
  /// }
  /// ```
  // void dispose() {
  //   _debounce?.cancel();
  //   WidgetsBinding.instance.removeObserver(this);
  // }

  /// Coordinates a Widget Tree capture according to `_debounce` and
  /// `_captureId` semantics.
  ///
  /// For the initial capture (right after the first frame), `debounce` is set
  /// to [false] so the capture runs immediately without waiting.
  /// For subsequent UI updates (scroll, drawer, dialogs, etc.), `debounce` is
  /// set to [true] so rapid changes are batched before performing a capture.
  ///
  /// Each request increments the internal capture id to distinguish versions
  /// and ensure that only the latest snapshot is processed.
  ///
  /// The actual capture routine (`_captureTree`) runs when appropriate,
  /// validating the id to ignore stale results.
  void _requestTreeCapture({bool debounce = false}) {
    if (!debounce) {
      _debounce?.cancel();
      _captureId++;
      _captureTree(id: _captureId);
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(Durations.short3, () {
      _captureId++;
      _captureTree(id: _captureId);
    });
  }

  ///
  void _requestTreeCaptureFromRouting() {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 16), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _captureId++;
        _routeTracker.isObserving = false;
        _captureTree(id: _captureId);
      });
    });
  }

  /// Captures the Widget Tree rooted at the navigator key's context and triggers
  /// further processing if the  structure has changed.
  ///
  /// In general terms this traverses the element subtree to produce a compact
  /// textual capture (widget `runtimeType` and `key` when present) in
  /// [processTreeSignature()], then offloads hashing/heavy String work to a
  /// background isolate to avoid blocking the UI thread.
  ///
  /// Notes:
  ///  - Heavy processing (hashing, long string work) runs in a background
  /// isolate; only lightweight traversal should occur on the UI thread.
  ///  - Always re-check the capture `id` and `_lastHash` after async work to
  /// avoid processing stale results.
  ///
  /// Also validates that the provided `id` matches the current `_captureId` and
  /// that the computed hash differs from `_lastHash`.
  ///
  /// When a genuine change is detected and the `id` is still valid, call
  /// [createLomTree()] function to create the first Lom class and their Root's
  /// children.
  ///
  /// Parameter:
  ///  - [id]: capture version to validate staleness (default: 0).
  ///
  /// Throw `FlutterError` if no navigator context is found.
  Future<void> _captureTree({int id = 0}) async {
    try {
      _currentRoute = _routeTracker.getCurrentRoute();

      if (_currentRoute == null) return;

      final BuildContext? context = _currentRoute!.subtreeContext;

      assert(() {
        if (context == null) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('SessionRecorder.init failed: context not found.'),
            ErrorHint(
              'Ensure you pass the SessionRecorderObserver to your app.',
            ),
            ErrorHint(
              'Example:\n'
              '  runApp(MaterialApp(observers: [SessionRecorderObserver()], ...));\n',
            ),
            ErrorHint(
              'This call is blocking and will throw to surface the incorrect'
              'initialization order immediately.',
            ),
          ]);
        }

        return true;
      }());

      if (context == null) return;

      if (!context.mounted) return;

      /// If a newer capture was requested while this one was running, abort
      /// processing.
      if (id != _captureId) return;

      final Element element = context as Element;

      /// Signs the `element` Tree Widgets
      final String signature = await SerializeTreeUtils.processTreeSignature(
        element,
      );

      /// If the stable structure did not change, no additional processing is
      /// performed.
      if (signature == _lastHash) return;

      _lastHash = signature;

      _lomDelegate.clearLom();

      final lom = _lomDelegate.createLomTree(element, signature);
      if (lom == null) return;

      /// Captures the first current `context` viewport
      if (context.mounted) {
        // ignore: use_build_context_synchronously
        _interactionDelegate!.captureViewportGeometry(context, null);
      }

      _chunkDelegate.addLom(lom);
    } catch (e, s) {
      debugPrint(" !! >> [Some error : $e, $s]");
      return;
    }
  }

  /// Periodic callback that sends the pending session record to the server.
  ///
  /// This method is intended to be registered as a [Timer] callback (for example
  /// via `Timer.periodic(Duration(seconds: 30), _sendSessionRecord)`).
  ///
  /// If there is no data available in the [Chunk], returns nothing until
  /// [InactivityTimer] cancels the [SessionRecorderTimer].
  Future<void> _sendSessionRecord(SessionRecorderParams params) async {
    if (_chunkDelegate.isChunkEmpty) return;

    final chunk = _chunkDelegate.chunk;

    final body = chunk.toJson();

    final uri = Uri.parse(params.endpoint!);

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

      debugPrint(">> [ Sended Data - SESSION RECORDER ]");
    } on SocketException catch (e) {
      debugPrint('!! Network error while sending data: $e');
    } on TimeoutException catch (e) {
      debugPrint('!! Request timed out: $e');
    } on FormatException catch (e) {
      debugPrint('!! Response format error: $e');
    } on HttpException catch (e) {
      debugPrint('!! HTTP exception: $e');
    } catch (e, st) {
      debugPrint('!! Unexpected error sending data: $e\n$st');
    }

    _lomDelegate.clearLom();
    _chunkDelegate.init(_sessionDelegate.getId());
  }

  // * ----- POINTER LISTENER ------ * //

  /// Forwards the [PointerDownEvent] to the [InteractionDelegate].
  void onPointerDown(PointerDownEvent e) {
    if (_disableRecord || !_serviceInitialized) return;
    _inactivityTimer.onInvokeInactivityTimer();
    _interactionDelegate!.onPointerDown(e);
  }

  /// Forwards the [PointerMoveEvent] to the [InteractionDelegate].
  void onPointerMove(PointerMoveEvent e) {
    if (_disableRecord || !_serviceInitialized) return;
    _inactivityTimer.onInvokeInactivityTimer();
    _interactionDelegate!.onPointerMove(e);
  }

  /// Forwards the [PointerUpEvent] to the [InteractionDelegate].
  void onPointerUp(PointerUpEvent e) {
    if (_disableRecord || !_serviceInitialized) return;
    _inactivityTimer.onInvokeInactivityTimer();
    if (_currentRoute != null) {
      _interactionDelegate!.onPointerUp(e, _currentRoute!.subtreeContext);
    }
  }

  /// Forwards the [PointerCancelEvent] to the [InteractionDelegate].
  void onPointerCancel(_) {
    if (_disableRecord || !_serviceInitialized) return;
    _inactivityTimer.onInvokeInactivityTimer();
    _interactionDelegate!.onPointerCancel();
  }

  // * ----- SCROLL NOTIFICATION ------ * //

  /// Forwards the [ScrollNotification] to the [InteractionDelegate] for
  /// processing.
  ///
  /// Returns `true` if the delegate handled the notification, `false` otherwise.
  bool handleScrollNotification(ScrollNotification s) {
    if (_disableRecord || !_serviceInitialized) return false;
    _inactivityTimer.onInvokeInactivityTimer();
    return _interactionDelegate!.handleScrollNotification(s);
  }
}
