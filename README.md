# Session Recorder Flutter

**Session Recorder Flutter** is a lightweight Flutter SDK for recording user
interactions and spatial UI structure during an application session.

It records metadata about gestures, scrolling, navigation, and visible layout
geometry.

It does **not** capture screenshots, text values, form values, or sensitive UI
content.

## Installation

Add the published package to your `pubspec.yaml`:

```yaml
dependencies:
  session_recorder_flutter: ^2.0.0
```

Then import the public API:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

## Compatibility

- **Dart:** `>=3.0.0 <4.0.0`
- **Platforms:** Android and iOS
- **Flutter:** see the minimum supported SDK version declared in `pubspec.yaml`

Web and desktop are not currently supported runtime targets.

## Quick Start

V2 requires only two integration steps:

1. Initialize `SessionRecorder`.
2. Add one `SessionRecorderWidget` around the application content.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SessionRecorder.init(
    const SessionRecorderConfig(
      endpoint: 'https://your-subdomain.ux-key.com/endpoint',
    ),
  );

  runApp(
    MaterialApp(
      home: const HomeScreen(),
      builder: (context, child) => SessionRecorderWidget(
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}
```

> [!IMPORTANT]
>
> Call `SessionRecorder.init()` once during application startup, after
> `WidgetsFlutterBinding.ensureInitialized()` and before `runApp()`.
>
> Do not initialize the recorder from a widget `build()` method or from
> frequently executed callbacks.

Using `MaterialApp.builder` is the recommended integration because it gives the
recorder a stable boundary around the application's navigable UI.

The same approach works with `MaterialApp.router`.

## What It Records

Session Recorder can record:

- taps, double taps, and long presses;
- drag and pinch gestures;
- scrolling activity;
- the spatial structure of the visible UI;
- layout geometry used to associate interactions with the UI.

Only UI that is currently materialized and visible is represented in the
captured structure.

The SDK does not record screenshots, text input values, form values, or the
contents of private UI fields.

## Configuration

```dart
const SessionRecorderConfig(
  endpoint: 'https://your-subdomain.ux-key.com/endpoint',
  debugLog: false,
  debugShowTree: false,
  debugSendSession: false,
);
```

### `endpoint`

Backend endpoint that receives Session Recorder chunks.

```text
https://your-subdomain.ux-key.com/endpoint
```

### `debugLog`

Enables internal SDK logs useful in Debug mode.

### `debugShowTree`

Displays the captured UI bounds in Debug mode.

### `debugSendSession`

Allows session chunks to be sent from Debug and Profile builds.

Release builds send normally.

## Optional Navigation Observer

`SessionNavigatorObserver` is optional in V2.

The recorder works with only `SessionRecorder.init()` and
`SessionRecorderWidget`. The observer adds explicit navigation signals so
post-navigation captures can be timed more precisely.

If you use it, create the observer once after initialization and keep it stable:

```dart
final sessionObserver = SessionNavigatorObserver();

MaterialApp(
  navigatorObservers: [
    anotherObserver,
    sessionObserver,
  ],
  home: const HomeScreen(),
  builder: (context, child) => SessionRecorderWidget(
    child: child ?? const SizedBox.shrink(),
  ),
);
```

Do not create the observer inside `build`.

Keep existing application observers and add the Session Recorder observer
alongside them.

Use a separate `SessionNavigatorObserver` instance for each Navigator.

## Advanced Integration

### Router / GoRouter

For router-based applications, use the same capture boundary with
`MaterialApp.router.builder`:

```dart
final sessionObserver = SessionNavigatorObserver();

final router = GoRouter(
  observers: [
    anotherObserver,
    sessionObserver,
  ],
  routes: [
    // ...
  ],
);

MaterialApp.router(
  routerConfig: router,
  builder: (context, child) => SessionRecorderWidget(
    child: child ?? const SizedBox.shrink(),
  ),
);
```

No GoRouter-specific Session Recorder integration is required.

The navigation observer remains optional.

### Existing MaterialApp builder

If your application already uses a builder, preserve it and wrap the final
widget it produces:

```dart
builder: (context, child) {
  final app = existingBuilder(context, child);

  return SessionRecorderWidget(
    child: app,
  );
}
```

Call the existing builder once and wrap its final result.

### Multiple Navigators

Applications with multiple Navigators may attach an optional
`SessionNavigatorObserver` to each one.

Use a different observer instance for every Navigator.

```dart
final rootObserver = SessionNavigatorObserver();
final shellObserver = SessionNavigatorObserver();
```

All observer instances report to the same Session Recorder runtime.

They provide navigation signals only and do not determine which UI subtree is
captured.

### Outer-wrapper convenience

An outer-wrapper integration is also supported:

```dart
SessionRecorderWidget.observer(
  builder: (observer) => MaterialApp(
    navigatorObservers: [
      anotherObserver,
      observer,
    ],
    home: const HomeScreen(),
  ),
);
```

`MaterialApp.builder` remains the recommended integration when a more precise
application boundary is desired.

## Runtime Notes

- Install only one `SessionRecorderWidget` for the same application boundary.
- User interactions do not trigger an HTTP request for every event; session data
  is grouped into chunks and reported periodically.
- Debug and Profile builds do not send session chunks unless
  `debugSendSession` is enabled.
- Release builds send session chunks normally.
- Scroll interactions preserve their start, trajectory, and end as one
  exploration sequence.

## Migrating from V1 (GitHub) to V2

V1 was distributed directly from GitHub. V2 is available as the published Dart
package.

### 1. Update the dependency

V1:

```yaml
dependencies:
  session_recorder_flutter:
    git: https://github.com/opentech-ux/session-recorder-flutter.git
```

V2:

```yaml
dependencies:
  session_recorder_flutter: ^2.0.0
```

The public import remains unchanged:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

### 2. Update initialization

V1:

```dart
SessionRecorder.instance.init(
  SessionRecorderParams(
    endpoint: 'https://your-subdomain.ux-key.com/endpoint',
  ),
);
```

V2:

```dart
SessionRecorder.init(
  const SessionRecorderConfig(
    endpoint: 'https://your-subdomain.ux-key.com/endpoint',
  ),
);
```

Initialize once in `main`, after:

```dart
WidgetsFlutterBinding.ensureInitialized();
```

and before `runApp()`.

### 3. Add the V2 capture boundary

`SessionRecorderWidget` is required.

The recommended integration is:

```dart
MaterialApp(
  home: const HomeScreen(),
  builder: (context, child) => SessionRecorderWidget(
    child: child ?? const SizedBox.shrink(),
  ),
);
```

For router-based applications, use the same approach with
`MaterialApp.router.builder`.

### 4. Navigation tracking is now optional

V1 required navigation observer integration.

In V2, `SessionNavigatorObserver` is optional. The required integration is only:

```text
SessionRecorder.init(...)
+
SessionRecorderWidget
```

If navigation observers are used, create them once outside `build` and use a
different instance for each Navigator.

### What improves in V2?

V2 introduces a new visible-only UI capture model, improved gesture and scroll
recording, and substantially reduced runtime and memory overhead compared with
V1.

Navigation, lifecycle handling, session reporting, and UI-change capture are
also more robust.

Applications that consume Session Recorder payloads directly should review the
V2 protocol documentation before upgrading.