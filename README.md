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

The required integration has two parts:

1. Initialize `SessionRecorder`.
2. Install one `SessionRecorderWidget`.

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
> Call `SessionRecorder.init()` **once**, during app startup. Do not call it from
> a widget `build()` method or from frequent callbacks.

`MaterialApp.builder` gives the recorder a precise boundary around the
application's navigable subtree. This setup is sufficient for LOM, gesture,
scroll, mutation, and LOM/event association capture.

## Optional Navigation Observer

`SessionNavigatorObserver` is not required for the SDK to work. It only adds
explicit navigation signals so post-navigation captures can be timed more
precisely.

Create it once after `SessionRecorder.init`, keep it in a stable app or router
owner, and preserve existing observers:

```dart
final sessionObserver = SessionNavigatorObserver(); // after init

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

Do not create it in `build` or in the `MaterialApp.builder` callback. It does
not define the capture boundary or replace existing observers.

## Router / GoRouter

GoRouter is optional. Keep the router and its observer stable, and place the
capture boundary in `MaterialApp.router.builder`:

```dart
final sessionObserver = SessionNavigatorObserver(); // after init

final router = GoRouter(
  observers: [anotherObserver, sessionObserver],
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

No GoRouter-specific SDK integration is required.

## Existing Builder

If the application already has a builder, preserve its composition and wrap
the final widget it produces:

```dart
builder: (context, child) {
  final app = existingBuilder(context, child);

  return SessionRecorderWidget(
    child: app,
  );
}
```

Call the existing builder once and wrap its final result.

## Convenience Outer-Wrapper Integration

`SessionRecorderWidget.observer` is a supported convenience that provides the
optional observer while wrapping the complete application:

```dart
SessionRecorderWidget.observer(
  builder: (observer) => MaterialApp(
    navigatorObservers: [anotherObserver, observer],
    home: const HomeScreen(),
  ),
);
```

Invoke it after `SessionRecorder.init` from a stable integration position. This
outer-wrapper form remains supported, but `MaterialApp.builder` is preferred
when a more precise capture boundary is wanted.

## Advanced: Multiple Navigators

Multiple navigators may each use their own `SessionNavigatorObserver` when
their navigation signals are wanted:

```dart
final rootSessionObserver = SessionNavigatorObserver(); // after init
final shellSessionObserver = SessionNavigatorObserver(); // after init

final router = GoRouter(
  observers: [rootSessionObserver],
  routes: [
    ShellRoute(
      observers: [shellSessionObserver],
      routes: [
        // ...
      ],
    ),
  ],
);
```

Do not reuse the same `NavigatorObserver` instance across navigators. Each
instance reports to the same Session Recorder runtime; observers remain
optional and do not determine the LOM root.

## What It Captures

- **Action events**: `tap`, `doubleTap`, `longPress`.
- **Exploration events**: `drag`, `pinch`, `scrollStart`, `scrollEnd`.
- **LOM snapshots**: spatial structure of the visible application subtree.
- **Session chunks**: periodic payloads sent to the configured endpoint.
- **Debug overlay**: optional visualization of captured LOM bounds.

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
> Endpoint validation is temporarily disabled for local endpoint testing.
> Before publishing or releasing the SDK, re-enable
> `SessionRecorderConfig.validate()` inside `SessionRecorder.init()`.

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
