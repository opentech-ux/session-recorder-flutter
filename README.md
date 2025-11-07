# Session Recorder Flutter

<img src="https://raw.githubusercontent.com/opentech-ux/session-recorder-flutter/refs/heads/main/assets/uxkey.png" width="50%">

A Flutter package for capturing and analyzing a structured record of user behavior sessions.

Designed for production use — efficient, isolated, and safe to integrate with **minimal** setup.

> [!important]
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
  session_record_flutter:
    git: https://github.com/opentech-ux/session-recorder-flutter.git
```

Now in your Dart code, you can use:

```dart
import 'package:session_recorder_flutter/session_recorder.dart';
```

## Usage

For proper integration of Session Recorder Flutter, the implementation is divided into two main components:

*   **Logic layer:** responsible for handling the internal mechanisms that analyze user interactions and session data.
*   **UI layer:** focuses on detecting, visualizing, and transmitting user behavior directly from the widget tree.

This separation ensures clean architecture, improved scalability, and easier debugging when integrating with complex Flutter applications.

> [!note]
>  
> Both components are completely __MANDATORY__.


### Logic Layer

Access the `SessionRecorder` instance via `SessionRecorder.instance`.

Then, invoke the `init()` method in your `main` method.

```dart
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
    // Important to add it before calling init method
    WidgetsFlutterBinding.ensureInitialized();

    final params = SessionRecorderParams(
        key: navigatorKey,
        endpoint: 'https://api.example.com/session',
    );

    SessionRecorder.instance.init(params);

    runApp(
        MyApp(navigatorKey: navigatorKey),
    );
}
```

The `init()` method requires the `SessionRecorderParams` object, which is the customizable configuration for the client.

There are some parameters to configure : 

*   `key`: Navigator key to access navigation context and capture widget tree snapshots.
*   `endpoint:` The backend endpoint (URI) that receives session data.
*   `disable`: Disable the session recording behavior __only for debugging__.

Check the class documentation for more details.

> [!important]
> 
> * `init` must be called only once — ideally from `main()`.
> You don’t need to wrap it in `WidgetsBinding.instance.addPostFrameCallback`, since `init` already handles that internally.
> * The `key` provided must be the same instance in your `MaterialApp`.
> * The `endpoint` URI String is provided by our customizable __API__
> * The `disable` is useful for development, testing, or when you need to temporarily stop analytics without removing the widget or service initialization. But has to be [false] in dev mode.


### UI Layer

To start capturing the user behavior, provide the `SessionRecorderWidget` in your `MaterialApp.builder`.

```dart
return MaterialApp(
    navigatorKey: key,
    builder: (context, child) => SessionRecorderWidget(
        child: child ?? SizedBox.shrink(),
    ),
);
```
> [!important]
> 
> This widget must be set **only once** in the entire app.


## Contact us

E-mail: **contact@ux-key.com**
