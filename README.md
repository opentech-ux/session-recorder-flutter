# Session Recorder Flutter

**Session Recorder Flutter** is a lightweight SDK for capturing user interactions and visible UI layout metadata during a Flutter application session.

It captures gestures, scrolling, navigation signals, and the position and size of visible UI elements without recording screenshots, displayed text, or form values.

> **Privacy by design:** Session Recorder captures interaction and layout metadata, not screenshots or screen content.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  session_recorder_flutter: ^2.0.0
```

Then import the public API:

```dart
import 'package:session_recorder_flutter/session_recorder_flutter.dart';
```

## Compatibility

* **Flutter:** `>=3.22.0`
* **Dart:** `>=3.4.0 <4.0.0`
* **Platforms:** Android and iOS

Web and desktop are not currently supported runtime targets.

## Quick Start

Integration requires only two steps:

1. Initialize `SessionRecorder`.
2. Add one `SessionRecorderWidget` around the application content.

These two steps are **required**. A `SessionNavigatorObserver` is
**recommended**, but not required, for better navigation signals and context.

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

Using `MaterialApp.builder` is the recommended integration because it provides a stable boundary around the application's navigable UI.

The same approach works with `MaterialApp.router`.

## Data Collection & Privacy

Session Recorder captures interaction and layout metadata required to understand how users interact with the visible application UI.

### Captured

Session Recorder can capture:

* tap, double-tap, and long-press interactions;
* drag and pinch gestures;
* interaction coordinates within the application viewport;
* scrolling activity and scroll sequences;
* navigation signals and hashed route segments when an observer is configured;
* the structure of UI elements that are currently visible;
* element positions and sizes within the visible application viewport;
* structural widget/type identifiers used to describe the visible UI.

Only UI elements that are currently materialized and visible are represented in the captured UI structure.

### Not Captured

Session Recorder does **not** capture:

* screenshots or screen pixels;
* displayed text content;
* text entered by users;
* form field values;
* image or media content.

Session data is grouped into chunks and sent to the endpoint configured by the application. User interactions do not trigger a separate HTTP request for every event.

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

Enables internal SDK logs useful during development.

### `debugShowTree`

Displays the captured UI bounds in Debug mode.

### `debugSendSession`

Allows session chunks to be sent from Debug and Profile builds.

Release builds send session chunks normally.

## Error Reporting / Custom Logger

Session Recorder is designed so that internal SDK errors do not interrupt your application.

If an internal error occurs, a capture or event may be skipped, but the host application continues running normally.

You can optionally provide a custom logger to send Session Recorder errors to your existing monitoring service.

```dart
SessionRecorder.init(
  SessionRecorderConfig(
    endpoint: 'https://your-subdomain.ux-key.com/endpoint',
    debugLog: false,
    logger: (level, message, {error, stackTrace}) {
      if (level.name != 'error') return;

      reportRecorderError(
        message,
        error,
        stackTrace,
      );
    },
  ),
);
```

The adapter is implemented by your application:

```dart
void reportRecorderError(
  String message,
  Object? error,
  StackTrace? stackTrace,
) {
  // Send the error to your monitoring provider.
}
```

You can connect it to tools such as:

| Provider             | Example use                          |
| -------------------- | ------------------------------------ |
| Sentry               | Report a handled exception or error. |
| Firebase Crashlytics | Record a non-fatal error.            |
| Datadog              | Send an error-level log.             |
| Bugsnag              | Report a handled error.              |

Session Recorder does not add dependencies for any monitoring provider.

When `debugLog` is disabled, diagnostic logs remain silent, but error-level messages are still sent to your custom logger when one is configured.

## Recommended Navigation Observer

`SessionNavigatorObserver` is recommended, not required. Without it, LOM
capture, mutations, gestures, scroll, event association and reporting still
work normally, without a missing-observer warning or error.

Session Recorder works with only:

```text
SessionRecorder.init(...)
+
SessionRecorderWidget
```

Adding a navigation observer provides explicit navigation signals so captures after route transitions can be timed more precisely.

Create the observer once after `SessionRecorder.init` and keep it stable:

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

Keep existing application observers and add the Session Recorder observer alongside them.

Use a separate `SessionNavigatorObserver` instance for each Navigator.

## Advanced Integration

### Router / GoRouter

For router-based applications, use the same capture boundary with `MaterialApp.router.builder`:

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

The navigation observer remains recommended, not required.

> [!IMPORTANT]
>
> For better navigation context, give your routes a stable `name`.
> Session Recorder uses `Route.settings.name` to generate anonymous route
> metadata. Unnamed screens are still recorded normally, but their route context
> cannot be included.
>
> When using `GoRouter` with `pageBuilder`, make sure the returned `Page`
> preserves the route name:
>
> ```dart
> CustomTransitionPage(
>   key: state.pageKey,
>   name: state.name,
>   child: const MyPage(),
> )
> ```

### Existing `MaterialApp.builder`

If your application already uses a builder, preserve it and wrap the final widget it produces:

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

Applications with multiple Navigators may attach an optional `SessionNavigatorObserver` to each one.

Use a different observer instance for every Navigator:

```dart
final rootObserver = SessionNavigatorObserver();
final shellObserver = SessionNavigatorObserver();
```

All observer instances report to the same Session Recorder runtime.

Observers provide navigation signals and best-effort anonymous context, without
determining which UI subtree is captured.

### Outer-Wrapper Convenience

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

`MaterialApp.builder` remains the recommended integration when a more precise application boundary is desired.

## Runtime Behavior

* Install only one `SessionRecorderWidget` for the same application boundary.
* Session data is grouped into chunks instead of sending one HTTP request for every interaction.
* Debug and Profile builds do not send session chunks unless `debugSendSession` is enabled.
* Release builds send session chunks normally.
* UI captures represent only elements that are materialized and visible at capture time.

## Obfuscated Builds

Session Recorder supports applications built with `--obfuscate`.

Flutter widgets known to the SDK use stable canonical names. Custom, third-party, or unrecognized widgets may appear with an obfuscated, best-effort `t` label.

Widget names are therefore not guaranteed to match between normal and obfuscated builds in every case.

This does not prevent Session Recorder from capturing visible UI geometry, gestures, or scrolling activity.

No obfuscation maps, symbol files, or additional configuration are required.

## Migrating from V1

V1 was distributed directly from GitHub. Version `2.0.0` is the first version distributed through pub.dev.

### 1. Update the Dependency

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

Update the public import.

V1:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

V2:

```dart
import 'package:session_recorder_flutter/session_recorder_flutter.dart';
```

### 2. Update Initialization

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

Initialize Session Recorder once in `main`, after:

```dart
WidgetsFlutterBinding.ensureInitialized();
```

and before `runApp()`.

### 3. Add the Capture Boundary

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

For router-based applications, use the same approach with `MaterialApp.router.builder`.

### 4. Navigation Tracking Is Now Optional

V1 required navigation observer integration.

In V2, `SessionNavigatorObserver` is optional. The required integration is only:

```text
SessionRecorder.init(...)
+
SessionRecorderWidget
```

The observer is recommended for navigation signals and anonymous context, not
required. If used, create it once outside `build` after initialization and use
a different instance for each Navigator.

### What Improves in V2?

V2 introduces a visible-only UI capture model, improved gesture and scroll recording, and substantially reduced runtime and memory overhead compared with V1.

Navigation, lifecycle handling, session reporting, and UI-change capture are also more robust.

Applications that consume Session Recorder payloads directly should review the V2 protocol documentation before upgrading.
