part of '../session_recorder_core.dart';

class TreeDetector {
  final SessionRecorder recorder;
  final LomTreeConfig config;

  TreeDetector({required this.recorder, this.config = const LomTreeConfig()});

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  bool _isPendingCapture = false;
  bool _isPostFrameQueued = false;
  bool _isBuilded = false;

  String _lastSignature = '';
  DateTime _lastCaptureTime = DateTime.fromMillisecondsSinceEpoch(0);

  VoidCallback? _lastOnBuildScheduled;

  ///
  void detect() {
    if (_isRunning) return;

    _isRunning = true;
    _buildOrDefer();
  }

  ///
  void _buildOrDefer() {
    final buildOwner = WidgetsBinding.instance.buildOwner;

    if (buildOwner == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isRunning) _buildOrDefer();
      });
      return;
    }

    /// Already builded the [BuildOwner] (e.g detect() called twice across a hot
    /// restart).
    if (_isBuilded) return;

    _lastOnBuildScheduled = buildOwner.onBuildScheduled;

    buildOwner.onBuildScheduled = () {
      _lastOnBuildScheduled?.call();

      if (!_isRunning) return;

      _isPendingCapture = true;

      if (!_isPostFrameQueued) {
        _isPostFrameQueued = true;
        WidgetsBinding.instance.addPostFrameCallback(_onRequestCapture);
      }
    };

    _isBuilded = true;
  }

  ///
  void _onRequestCapture(Duration _) {
    _isPostFrameQueued = false;

    if (!_isRunning || !_isPendingCapture) return;

    _isPendingCapture = false;

    final DateTime now = DateTime.now();

    /// Minimum [200] ms between consecutive captures
    if (now.difference(_lastCaptureTime).inMilliseconds < 200) {
      return;
    }

    /// Capture queued
    captureTree(null);
  }

  ///
  void captureTree(Element? rootElement) {
    Future.microtask(() {
      final lom = LomTreeInspector.captureLom(rootElement, config: config);

      if (lom == null) return;

      /// If the stable structure did not change, no additional processing is
      /// performed.
      if (lom.signature == _lastSignature) return;

      _lastSignature = lom.signature;
      _lastCaptureTime = DateTime.now();

      _emit(lom);
    });
  }

  ///
  void _emit(LomAbstract lom) {
    recorder._recordLom(lom as Lom);
  }
}
