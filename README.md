# Session Recorder Flutter

**Session Recorder Flutter** is a lightweight Flutter SDK for capturing user
interaction sessions and spatial UI snapshots.

It records **metadata** about gestures, scrolls, navigation, and layout
geometry. It does **not** capture text values, form values, screenshots, or
sensitive user content.

> [!IMPORTANT]
>
> This package is currently consumed from **Git**. Pub.dev publication will come
> later, once the V2 runtime is validated.

## What It Captures

- **Action events**: `tap`, `doubleTap`, `longPress`.
- **Exploration events**: `drag`, `pinch`, `scrollStart`, `scrollEnd`.
- **LOM snapshots**: spatial structure of the active route.
- **Session chunks**: periodic payloads sent to the configured endpoint.
- **Debug overlay**: optional visualization of captured LOM bounds.

## Installation

Add the package to your app `pubspec.yaml`:

```yaml
dependencies:
  session_recorder_flutter:
    git: https://github.com/opentech-ux/session-recorder-flutter.git
```

Then import the public API:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

## Compatibility

- **Dart**: `>=3.0.0 <4.0.0`
- **Flutter**: `>=3.10.0`

## Basic Usage

The integration has three parts:

1. Initialize `SessionRecorder`.
2. Wrap the app with `SessionRecorderWidget`.
3. Attach `SessionNavigatorObserver` to the navigator.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SessionRecorder.init(
    const SessionRecorderConfig(
      endpoint: 'https://demo-client.ux-key.com/endpoint',
      debugLog: true,
    ),
  );

  runApp(
    SessionRecorderWidget(
      child: MaterialApp(
        navigatorObservers: [SessionNavigatorObserver()],
        home: const HomeScreen(),
      ),
    ),
  );
}
```

> [!IMPORTANT]
>
> Call `SessionRecorder.init()` **once**, during app startup. Do not call it from
> a widget `build()` method or from frequent callbacks.

## Router Usage

For `MaterialApp.router`, attach `SessionNavigatorObserver` to your router
configuration:

```dart
SessionRecorderWidget(
  child: MaterialApp.router(
    routerConfig: GoRouter(
      observers: [SessionNavigatorObserver()],
      routes: [
        // ...
      ],
    ),
  ),
);
```

For nested navigators, such as `ShellRoute`, attach one observer per navigator
that should trigger LOM captures.

## Configuration

```dart
const SessionRecorderConfig(
  endpoint: 'https://demo-client.ux-key.com/endpoint',
  debugLog: true,
  debugShowTree: false,
  debugSendSession: false,
);
```

Options:

- `endpoint`: backend endpoint that receives session chunks.
- `debugLog`: enables SDK internal logs.
- `debugShowTree`: paints captured LOM bounds in debug builds.
- `debugSendSession`: sends chunks in debug mode. Release builds always send.

## Endpoint Format

The production endpoint format is:

```text
https://[subdomain].ux-key.com/endpoint
```

Example:

```text
https://demo-client.ux-key.com/endpoint
```

> [!WARNING]
>
> Endpoint validation can be temporarily disabled while testing local endpoints.
> Before publishing or releasing the SDK, re-enable `SessionRecorderConfig.validate()`
> inside `SessionRecorder.init()`.

## Runtime Notes

- `SessionRecorderWidget` should be installed **once** in the app tree.
- Chunks are sent periodically; user interactions do not force immediate HTTP uploads.
- In debug mode, chunks are not sent unless `debugSendSession` is `true`.
- The payload contains layout geometry and zone identifiers, not private UI content.

> [!NOTE]
>
> During scroll, the SDK keeps the sequence
> `scrollStart -> drag... -> scrollEnd`. The `drag` points represent the scroll
> trajectory and are interpreted as part of the same scroll exploration.
