## 2.0.0

### Breaking

- New V2 API: use `SessionRecorder.init(SessionRecorderConfig(...))` instead of the V1 singleton and parameters.
- Payload changes require custom consumers to follow the V2 protocol/payload documentation.

### Added

- Visible-only LOM capture of the application's UI structure.
- Optional `SessionNavigatorObserver`; only initialization and `SessionRecorderWidget` are required.

### Improved

- More reliable gesture and scroll recording.
- Significant performance and memory improvements.
- More robust navigation, lifecycle handling, and reporting.

### Documentation

- Simplified V1-to-V2 migration guide and recommended `MaterialApp.builder` / `MaterialApp.router.builder` integration.

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
