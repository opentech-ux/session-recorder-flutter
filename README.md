# Session Recorder Flutter

A Flutter package for capturing and analyzing a structured record of user behavior sessions.

Designed for production use — efficient, isolated, and safe to integrate with **minimal** setup.

> [!warning]
> 
> This package is in beta and some things may break your app.


## Features

*   Captures the user behavior as the **taps, double-taps, scrolls, long presses and zooms** gestures in real time.
*   Serialize widget trees and viewport positions efficiently.
*   Build-in HTTP upload of session data.

## Installing

Add the dependency in your `pubspec.yaml`:

```yaml
dependencies:
  session_recorder_flutter:
    git: https://github.com/opentech-ux/session-recorder-flutter.git
```

Now in your Dart code, you can use:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

## Usage

For proper integration of Session Recorder Flutter, the implementation is divided into three main components:

*   **Logic layer:** responsible for handling the internal mechanisms that analyze user interactions and session data.
*   **Navigator layer:** responsible for handling the navigation between routes to capture correctly the Widget Tree.
*   **UI layer:** focuses on detecting, visualizing, and transmitting user behavior directly from the widget tree.

This separation ensures clean architecture, improved scalability, and easier debugging when integrating with complex Flutter applications.

> [!note]
>  
> Every components are completely __MANDATORY__.


### Logic Layer

Access the `SessionRecorder` instance via `SessionRecorder.instance`.

Then, invoke the `init()` method in your `main` method.

```dart
void main() {
    // Important to add it before calling init method
    WidgetsFlutterBinding.ensureInitialized();

    final params = SessionRecorderParams(
        endpoint: 'https://api.example.com/session',
    );

    SessionRecorder.instance.init(params);

    runApp(MyApp());
}
```

The `init()` method requires the `SessionRecorderParams` object, which is the customizable configuration for the client.

There are some parameters to configure : 

*   `endpoint:` The backend endpoint (URI) that receives session data.
*   `disable`: Disable the session recording behavior __only for debugging__.

Check the class documentation for more details.

> [!important]
> 
> * `init` must be called only once — ideally from `main()`.
> You don’t need to wrap it in `WidgetsBinding.instance.addPostFrameCallback`, since `init` already handles that internally.
> * The `endpoint` URI String is provided by our customizable __API__
> * The `disable` is useful for development, testing, or when you need to temporarily stop analytics without removing the widget or service initialization. But has to be [false] in dev mode.


### Navigator Layer

To capture every Widget Tree correctly, provide the `SessionRecorderObserver` in your `MaterialApp` observers list.

```dart
return MaterialApp(
    navigatorObservers: [
        SessionRecorderObserver(),
    ],
    [...]
)
```

In case of using another Navigator Package like [go_router](https://pub.dev/packages/go_router). You may attach multiple observers (e.g., when using multiple `ShellRoute` navigators).

```dart
return MaterialApp.router(
    routerConfig: GoRouter(
        observers: [SessionRecorderObserver()],
        routes: [...],
    ),
);
```

### UI Layer

To start capturing the user behavior, provide the `SessionRecorderWidget` in your `MaterialApp.builder`.

```dart
return MaterialApp(
    navigatorObservers: [SessionRecorderObserver()],
    builder: (context, child) => SessionRecorderWidget(
        child: child!,
    ),
);
```
> [!important]
> 
> This widget must be set **only once** in the entire app.

