## 2.0.1

### Changed

* **ADD** Endpoint validation, otherwise shows a ERROR message.
* Invalid endpoints leave the SDK in no-op mode; errors are reported through the configured logger.

## 2.0.0

> **Breaking:** This release introduces a new public API and integration model.

### Breaking

* Requires Flutter 3.22.0 or later and Dart `>=3.4.0 <4.0.0`.
* Replaced the V1 singleton initialization with:
  `SessionRecorder.init(SessionRecorderConfig(...))`.
* `SessionRecorderWidget` is now required as the capture boundary around the application UI.
* Changed the public package entrypoint to:
  `package:session_recorder_flutter/session_recorder_flutter.dart`.
* UI structure capture now represents only materialized elements visible within the application viewport.

### Added

* Visible-only UI structure capture using application viewport coordinates.
* Automatic UI-change detection and capture after relevant layout updates.
* Optional `SessionNavigatorObserver` for more precise post-navigation capture timing.
* Optional `screenNameProvider` for authoritative logical screen context in complex or router-based navigation.
* Debug visualization of captured UI bounds through `debugShowTree`.

### Improved

* Gesture capture for taps, double taps, long presses, drags, and pinch interactions.
* Scroll recording and post-scroll UI capture.
* LOM deduplication to avoid reporting unchanged UI structures.
* Runtime CPU and memory usage compared with V1.
* Navigation transitions, lifecycle handling, session reporting, and capture scheduling.

### Integration

The minimum integration is now:

```text
SessionRecorder.init(...)
+
SessionRecorderWidget
```

`SessionNavigatorObserver` is optional.

`MaterialApp.builder` and `MaterialApp.router.builder` are the recommended integration points.

### Documentation

* Added updated installation and Quick Start documentation.
* Added a Data Collection & Privacy section describing what the SDK captures and does not capture.
* Added V1-to-V2 migration instructions.
* Added guidance for `MaterialApp`, `MaterialApp.router`, GoRouter, existing builders, multiple Navigators, and obfuscated builds.


## 1.1.1

- **FIXED** the bug that captured the tree too early.
- **FIXED** the bug that did not capture the tree during an animation.
- **FIXED** the bug that did not capture the tap action event.
- **FIXED** the bug that did not correctly send a session during tree capture.

## 1.1.0

> Note: This release has breaking changes.

- **BREAKING**(session_recorder_flutter): SessionRecorderFlutter refactor ([d0edaaa37022d94651dabe33a31eb3d978e4470b](https://github.com/opentech-ux/session-recorder-flutter/commit/d0edaaa37022d94651dabe33a31eb3d978e4470b))

This version introduces the new `SessionRecorderObserver` class.
It replaces the old `NavigatorKey` in the `SessionRecorderParams`, which has been deprecated.
Check the `README.md` for more information.

## 1.0.2

- **ADD** library_type in chunk
- **ADD** try-catch handle in http

## 1.0.1

- **INIT** beta release
