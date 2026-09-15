import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_recorder.dart';
import 'package:session_recorder_flutter/src/utils/recorder_callback.dart';

/// Mixin that pauses and resumes the tracker based on `[AppLifecycleState]`.
///
/// It extends `[WidgetsBindingObserver]` to observe app lifecycle events
/// (pause/resume/etc.) and to manage timers and periodic uploads safely.
mixin SessionLifecycleObserver<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    runRecorderCallback('lifecycle registration', () {
      WidgetsBinding.instance.addObserver(this);
    });
  }

  @override
  void dispose() {
    runRecorderCallback('lifecycle unregistration', () {
      WidgetsBinding.instance.removeObserver(this);
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        runRecorderCallback(
          'lifecycle resume',
          SessionRecorder.engine.controller.startReporting,
        );
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        onSessionSuspended();
        runRecorderCallback(
          'lifecycle suspension',
          SessionRecorder.engine.controller.stopReporting,
        );
    }

    super.didChangeAppLifecycleState(state);
  }

  void onSessionSuspended() {}
}
