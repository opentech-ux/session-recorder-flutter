# Session Recorder Flutter Example

This example demonstrates the main Session Recorder Flutter integration and
runtime features.

It includes:

- `SessionRecorder.init`;
- `SessionRecorderWidget`;
- `SessionNavigatorObserver`;
- stable named routes;
- taps and double taps;
- long presses;
- drag gestures;
- pinch gestures;
- scrolling;
- dialogs and overlays;
- custom SDK error logging.

## Run

Replace the example endpoint in `lib/main.dart`:

```dart
endpoint: 'https://your-subdomain.ux-key.com/endpoint',
````

Then run:

```bash
flutter run
```

`debugSendSession` is enabled in the example so sessions can be sent while
running in Debug or Profile mode.

## Navigation

The example uses standard Flutter navigation with stable route names:

```dart
initialRoute: 'home',
```

and:

```dart
Navigator.of(context).pushNamed('details');
```

`SessionNavigatorObserver` is recommended for explicit navigation signals.

For complex router-based applications or applications with multiple
`Navigator` instances, see the main package `README` for
`screenNameProvider` integration.