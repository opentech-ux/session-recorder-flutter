# Session Record UX

<img src="https://gitlab.ux-key.csd/-/ide/project/UX-Key/opentech-ux-mobile-session-record-development-kit/edit/main/-/assets/uxkey.png" width="50%">

A Flutter package for capturing and analyzing a structured record of user behavior sessions.

Designed for production use — efficient, isolated, and safe to integrate with **minimal** setup.

> [!important]
> This package is in beta and some things may break your app.

## Features

*   Captures the user behavior as the **taps, double-taps, scrolls, long presses and zooms** gestures in real time.
*   Serialize widget trees and viewport positions efficiently.
*   Build-in HTTP upload of session data.

## Installing

Add the dependency: 

```bash
$ flutter pub add session_record_ux
```

This will add a line like this to your package's pubspec.yaml (and run an implicit flutter pub get):

```yaml
dependencies:
  session_record_ux: ^1.0.0
```

Now in your Dart code, you can use:

```dart
import 'package:session_record_ux/session_record.dart';
```

## Usage

For proper integration of Session Record UX, the implementation is divided into two main components:

*   **Logic layer:** responsible for handling the internal mechanisms that analyze user interactions and session data.
*   **UI layer:** focuses on detecting, visualizing, and transmitting user behavior directly from the widget tree.

This separation ensures clean architecture, improved scalability, and easier debugging when integrating with complex Flutter applications.

> [!note]
> Both components are completely __MANDATORY__.

### Logic Layer

Access the `SessionRecord` instance via `SessionRecord.instance`.

Then, invoke the `init()` method in your `main` method.

```dart
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
    // Important to add it before calling init method
    WidgetsFlutterBinding.ensureInitialized();

    final params = SessionRecordParams(
        key: navigatorKey,
        endpoint: 'https://api.example.com/session',
    );

    SessionRecord.instance.init(params);

    runApp(
        MyApp(navigatorKey: navigatorKey),
    );
}
```

The `init()` method requires the `SessionRecordParams` object, which is the customizable configuration for the client.

There are some parameters to configure : 

*   `key`: Navigator key to access navigation context and capture widget tree snapshots.
*   `endpoint:` The backend endpoint (URI) that receives session data.
*   `disable`: Disable the session recording behavior __only for debugging__.

Check the class documentation for more details.

> [!important]
> * `init` must be called only once — ideally from `main()`.
> You don’t need to wrap it in `WidgetsBinding.instance.addPostFrameCallback`, since `init` already handles that internally.
> * The `key` provided must be the same instance in your `MaterialApp`.
> * The `endpoint` URI String is provided by our customizable __API__
> * The `disable` is useful for development, testing, or when you need to temporarily stop analytics without removing the widget or service initialization. But has to be [false] in dev mode.

### UI Layer

To start capturing the user behavior, provide the `SessionRecordWidget` in your `MaterialApp.builder`.

```dart
return MaterialApp(
    navigatorKey: key,
    builder: (context, child) => SessionRecordWidget(
        child: child ?? SizedBox.shrink(),
    ),
);
```
> [!important]
> This widget must be set **only once** in the entire app.

## Contact us

E-mail: **contact@ux-key.com**
