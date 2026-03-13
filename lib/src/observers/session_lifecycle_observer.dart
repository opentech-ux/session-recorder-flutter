part of '../session_recorder_core.dart';

/// Mixin that pauses and resumes the tracker based on [AppLifecycleState].
mixin SessionLifecycleObserver<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  SessionRecorder get _recorder => SessionRecorder.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _recorder._startReporting();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _recorder._stopReporting();
    }

    super.didChangeAppLifecycleState(state);
  }
}
