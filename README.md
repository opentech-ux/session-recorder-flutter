# Session Recorder Flutter

**Session Recorder Flutter** is a lightweight SDK for recording user interactions and the structure of the visible UI.

It captures gestures, scrolling, navigation context, and visible element geometry without recording screenshots, displayed text, or form values.

> Session Recorder captures interaction and layout metadata, not screen content.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  session_recorder_flutter: ^2.0.0
```

Import the public API:

```dart
import 'package:session_recorder_flutter/session_recorder_flutter.dart';
```

## Compatibility

* **Flutter:** `>=3.22.0`
* **Dart:** `>=3.4.0 <4.0.0`
* **Platforms:** Android and iOS

Web and desktop are not currently supported.

## Quick Start

Integration requires only two steps:

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

Call `SessionRecorder.init()` once during application startup, after:

```dart
WidgetsFlutterBinding.ensureInitialized();
```

and before `runApp()`.

`MaterialApp.builder` is the recommended integration point.

The same approach can be used with `MaterialApp.router.builder`.

**That's all that is required.**

> Navigation options can be added when more precise navigation context is needed.

## Navigation

Session Recorder works without a navigation observer.

For standard Flutter navigation, `SessionNavigatorObserver` is recommended to provide explicit navigation signals and improve capture timing after route changes.

```dart
final sessionObserver = SessionNavigatorObserver();

MaterialApp(
  navigatorObservers: [
    sessionObserver,
  ],
  home: const HomeScreen(),
  builder: (context, child) => SessionRecorderWidget(
    child: child ?? const SizedBox.shrink(),
  ),
);
```

Create the observer once and keep it stable.

> If your application uses multiple `Navigator` instances, such as nested
> navigation or shell routes, use a separate `SessionNavigatorObserver()` for each
> Navigator.

### Complex Navigation

For router-based applications or applications with complex navigation, you can
provide the current logical screen name directly:

```dart
SessionRecorder.init(
  SessionRecorderConfig(
    endpoint: 'https://your-subdomain.ux-key.com/endpoint',
    screenNameProvider: () => navigationState.currentScreenName,
  ),
);
```

`navigationState.currentScreenName` is only an example. The callback should
return the logical screen name from your application's own navigation system.

For complex navigation, use `screenNameProvider` when you need more accurate screen context. Without it, recording still works, but navigation context may be less precise.

For example, with [GoRouter](https://pub.dev/packages/go_router):

```dart
screenNameProvider: () {
  final configuration = router.routerDelegate.currentConfiguration;

  if (configuration.isEmpty) {
    return null;
  }

  return configuration.last.route.name;
},
```

Give relevant routes stable names:

```dart
GoRoute(
  name: 'home',
  path: '/home',
  builder: (context, state) => const HomeScreen(),
),

GoRoute(
  name: 'details',
  path: '/details',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    name: state.name,
    child: const DetailsScreen(),
    transitionsBuilder: ...
  ),
),
```

If you use `pageBuilder` with a custom `Page`, such as `CustomTransitionPage`, also preserve the route `name` on the returned pages.

> Screen names are hashed before being stored or sent.

`screenNameProvider` is optional.

## Configuration

```dart
SessionRecorderConfig(
  endpoint: 'https://your-subdomain.ux-key.com/endpoint',
  debugLog: false,
  debugShowTree: false,
  debugSendSession: false,
  screenNameProvider: null,
  logger: null,
);
```

| Option               | Purpose                                                   |
| -------------------- | --------------------------------------------------------- |
| `endpoint`           | Endpoint that receives session data.                      |
| `debugLog`           | Enables SDK diagnostic logs.                              |
| `debugShowTree`      | Shows captured UI bounds in Debug.                        |
| `debugSendSession`   | Allows sessions to be sent from Debug and Profile builds. |
| `screenNameProvider` | Provides a logical screen name for complex navigation.    |
| `logger`             | Receives SDK logs and errors through a custom callback.   |

Release builds send session data normally.

## Data Collection & Privacy

Session Recorder captures interaction and layout metadata used to understand how users interact with the visible application UI.

### Captured

* Taps, double taps, and long presses.
* Drag and pinch gestures.
* Interaction coordinates.
* Scrolling activity.
* Visible UI structure.
* Positions and sizes of visible UI elements.
* Structural widget/type identifiers.
* Hashed navigation context when available.
* Session and timing metadata required to associate interactions with captures.

Only UI elements that are currently materialized and visible are represented in the captured UI structure.

### Not Captured

Session Recorder does **not** capture:

* Screenshots or screen pixels.
* Displayed text content.
* Text entered by users.
* Form field values.
* Image or media content.

Session data is grouped into chunks and sent to the configured endpoint.

A separate HTTP request is not sent for every user interaction.

## Error Reporting

Session Recorder is designed so that internal SDK errors do not interrupt your application.

If needed, you can forward SDK errors to your existing monitoring service:

```dart
SessionRecorder.init(
  SessionRecorderConfig(
    endpoint: 'https://your-subdomain.ux-key.com/endpoint',
    logger: (level, message, {error, stackTrace}) {
      if (level.name == 'error') {
        reportRecorderError(
          message,
          error,
          stackTrace,
        );
      }
    },
  ),
);
```

The error reporter belongs to your application:

```dart
void reportRecorderError(
  String message,
  Object? error,
  StackTrace? stackTrace,
) {
  // Send the error to your monitoring provider.
}
```

Session Recorder does not depend on any error-monitoring provider.

## Obfuscated Builds

Applications built with `--obfuscate` are supported without additional configuration.

Visible UI geometry, gestures, and scrolling continue working normally.

Some custom or third-party widget type names may appear obfuscated.

## Migrating from V1

V1 was distributed directly from GitHub.

Version `2.0.0` is the first version distributed through pub.dev.

### Dependency

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

### Import

V1:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

V2:

```dart
import 'package:session_recorder_flutter/session_recorder_flutter.dart';
```

### Initialization

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

### Capture Boundary

V2 requires one `SessionRecorderWidget` around the application content:

```dart
MaterialApp(
  home: const HomeScreen(),
  builder: (context, child) => SessionRecorderWidget(
    child: child ?? const SizedBox.shrink(),
  ),
);
```

### What Improves in V2?

V2 introduces a visible-only UI capture model, improved gesture and scroll recording, and substantially reduced runtime and memory overhead compared with V1.

Navigation, lifecycle handling, session reporting, and UI-change capture are also more robust.

Applications that consume Session Recorder payloads directly should review the V2 protocol documentation before upgrading.
