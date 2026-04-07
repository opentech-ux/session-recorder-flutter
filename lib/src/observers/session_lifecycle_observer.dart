import 'package:flutter/material.dart';

import 'package:session_recorder_flutter/src/session/session_controller_internal.dart';

/// Mixin that pauses and resumes the tracker based on `[AppLifecycleState]`.
///
/// It extends `[WidgetsBindingObserver]` to observe app lifecycle events
/// (pause/resume/etc.) and to manage timers and periodic uploads safely.
mixin SessionLifecycleObserver<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  SessionControllerInternal get controller;

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
        controller.startReporting();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        onSessionSuspended();
        controller.stopReporting();
    }

    super.didChangeAppLifecycleState(state);
  }

  void onSessionSuspended() {}
}
