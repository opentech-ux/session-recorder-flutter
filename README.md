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
- **LOM snapshots**: spatial structure of the visible application subtree.
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

## Recommended Usage

The required integration has two parts:

1. Initialize `SessionRecorder`.
2. Install `SessionRecorderWidget` once in `MaterialApp.builder` or
   `MaterialApp.router.builder`.

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

The builder placement is recommended because it creates a more precise capture
boundary and avoids traversing unnecessary `MaterialApp` infrastructure. The
routing subtree remains inside the recorder, including `Router`, root and nested
`Navigator` instances, `ShellRoute` content, navigator overlays, routes,
dialogs, modal and persistent bottom sheets, drawers, popup menus, dropdowns,
routing `OverlayEntry` instances, snack bars, and scaffold content. Pointer
events and scroll notifications are captured only inside the wrapped subtree.

For a normal routed `MaterialApp` or `MaterialApp.router`, the example's null
fallback is safe. In a builder-only application where `child` is null, wrap the
application or routing widget that the builder already creates instead of using
an empty fallback.

## Router Usage

`MaterialApp.router` uses the same explicit boundary:

```dart
MaterialApp.router(
  routerConfig: router,
  builder: (context, child) => SessionRecorderWidget(
    child: child ?? const SizedBox.shrink(),
  ),
);
```

No GoRouter-specific SDK integration is required. `ShellRoute` and nested
navigators are naturally part of the wrapped routing subtree.

`SessionNavigatorObserver` is optional. Attach it to navigators whose
transitions should provide more precise LOM capture timing:

```dart
final router = GoRouter(
  observers: [SessionNavigatorObserver()],
  routes: [
    // ...
  ],
);
```

The observer does not locate the capture root and is not required for initial
capture, gestures, scrolls, or ordinary UI mutations.

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

Call the existing builder exactly once. This keeps provider, localization,
custom `MediaQuery`, theme, accessibility, and third-party wrappers inside the
capture boundary. UI deliberately created outside the wrapped result is not
captured.

## Supported Outer Wrapper

The simpler outer-wrapper integration remains fully supported:

```dart
SessionRecorderWidget(
  child: MaterialApp(
    home: const HomeScreen(),
  ),
);
```

It behaves the same functionally but captures a broader subtree that includes
more `MaterialApp` infrastructure. The recommended builder placement reduces
that unnecessary traversal; it does not promise a large CPU improvement.

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
