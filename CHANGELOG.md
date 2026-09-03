## 2.0.0

- **BREAKING** Refactored the public API around `SessionRecorder.init`, `SessionRecorderConfig`, `SessionRecorderWidget`, and `SessionNavigatorObserver`.
- **ADDED** Visible-only LOM capture in viewport coordinates with a stable physical capture boundary and `Lom`/`LomRef` deduplication.
- **ADDED** Recommended `MaterialApp.builder` integration with an optional navigation observer.
- **ADDED** Navigation, mutation, interaction-consequence, and post-scroll capture scheduling.
- **ADDED** Tap, double tap, long press, drag, pinch, and scroll gesture capture.
- **ADDED** A required top-level `framework: "Flutter"` discriminator in every chunk.
- **ADDED** Reporter safeguards for concurrent flushes, HTTP timeout, and short in-memory retry.
- **IMPROVED** Profile/Release robustness, memory use, and runtime performance compared with V1.
- **UPDATED** Documentation and examples for the V2 integration and viewport-based event/LOM association.

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
