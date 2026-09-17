import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:session_recorder_flutter/session_recorder_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SessionRecorder.init(
    SessionRecorderConfig(
      endpoint: 'https://your-subdomain.ux-key.com/endpoint',

      /// Development options.
      debugLog: true,
      debugShowTree: false,
      debugSendSession: true,

      /// Optional custom logger.
      logger: (level, message, {error, stackTrace}) {
        if (level.name != 'error') return;

        debugPrint('Session Recorder error: $message');

        if (error != null) {
          debugPrint('$error');
        }

        if (stackTrace != null) {
          debugPrint('$stackTrace');
        }
      },

      /// For complex router-based navigation, you can optionally provide
      /// the application's current logical screen:
      ///
      /// screenNameProvider: () => navigationState.currentScreenName,
    ),
  );

  /// Create the observer once, after SessionRecorder.init().
  final sessionObserver = SessionNavigatorObserver();

  runApp(ExampleApp(sessionObserver: sessionObserver));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.sessionObserver});

  final SessionNavigatorObserver sessionObserver;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Session Recorder Example',
      debugShowCheckedModeBanner: false,

      /// The observer is recommended for explicit navigation signals.
      ///
      /// If your application uses multiple `Navigator` instances, such as nested
      /// navigation or shell routes, use a separate `SessionNavigatorObserver()`
      /// for each Navigator.
      navigatorObservers: [sessionObserver],

      /// Stable route names improve automatic navigation context.
      initialRoute: 'home',
      onGenerateRoute: _onGenerateRoute,

      /// Required UI integration.
      builder: (context, child) =>
          SessionRecorderWidget(child: child ?? const SizedBox.shrink()),
    );
  }
}

Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case 'home':
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const HomePage(),
      );

    case 'details':
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const DetailsPage(),
      );

    default:
      return null;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showExampleDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Example dialog'),
        content: const Text(
          'Dialogs and overlays do not require additional '
          'Session Recorder integration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session Recorder Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Try the interactions below',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This example demonstrates taps, gestures, scrolling, '
            'navigation and visible UI capture.',
          ),
          const SizedBox(height: 24),

          ExampleCard(
            title: 'Tap',
            description: 'A regular button interaction.',
            child: FilledButton(
              onPressed: () {
                _showMessage(context, 'Tap detected');
              },
              child: const Text('Tap me'),
            ),
          ),

          ExampleCard(
            title: 'Double tap',
            description: 'Tap the area twice quickly.',
            child: GestureDetector(
              onDoubleTap: () {
                _showMessage(context, 'Double tap detected');
              },
              child: const GestureArea(
                icon: Icons.touch_app,
                label: 'Double tap here',
              ),
            ),
          ),

          ExampleCard(
            title: 'Long press',
            description: 'Press and hold the area.',
            child: GestureDetector(
              onLongPress: () {
                _showMessage(context, 'Long press detected');
              },
              child: const GestureArea(
                icon: Icons.pan_tool_alt,
                label: 'Press and hold',
              ),
            ),
          ),

          const ExampleCard(
            title: 'Drag',
            description: 'Drag the circle horizontally.',
            child: DragExample(),
          ),

          const ExampleCard(
            title: 'Pinch',
            description: 'Use two fingers to resize the box.',
            child: PinchExample(),
          ),

          ExampleCard(
            title: 'Navigation',
            description: 'Open another named Flutter route.',
            child: FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pushNamed('details');
              },
              child: const Text('Open details'),
            ),
          ),

          ExampleCard(
            title: 'Dialog',
            description: 'Open a standard Flutter dialog.',
            child: OutlinedButton(
              onPressed: () {
                _showExampleDialog(context);
              },
              child: const Text('Show dialog'),
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'Scrollable content',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scroll the list to generate scroll activity and '
            'visible UI updates.',
          ),
          const SizedBox(height: 12),

          ...List.generate(
            20,
            (index) => ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text('Item ${index + 1}'),
              subtitle: const Text('Example scrollable item'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showMessage(context, 'Item ${index + 1} tapped');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers_outlined, size: 72),
              const SizedBox(height: 24),
              const Text(
                'Named navigation route',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'This screen uses the stable logical route name '
                '"details".',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DragExample extends StatefulWidget {
  const DragExample({super.key});

  @override
  State<DragExample> createState() => _DragExampleState();
}

class _DragExampleState extends State<DragExample> {
  double _position = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const size = 56.0;
          final maxPosition = (constraints.maxWidth - size).clamp(
            0.0,
            double.infinity,
          );

          return Stack(
            children: [
              Positioned(
                left: _position.clamp(0.0, maxPosition),
                top: 17,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _position = (_position + details.delta.dx).clamp(
                        0.0,
                        maxPosition,
                      );
                    });
                  },
                  child: const CircleAvatar(
                    radius: size / 2,
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PinchExample extends StatefulWidget {
  const PinchExample({super.key});

  @override
  State<PinchExample> createState() => _PinchExampleState();
}

class _PinchExampleState extends State<PinchExample> {
  double _scale = 1;
  double _baseScale = 1;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Center(
        child: GestureDetector(
          onScaleStart: (_) {
            _baseScale = _scale;
          },
          onScaleUpdate: (details) {
            setState(() {
              _scale = (_baseScale * details.scale).clamp(0.7, 1.8);
            });
          },
          child: Transform.scale(
            scale: _scale,
            child: Container(
              width: 90,
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.pinch, size: 36),
            ),
          ),
        ),
      ),
    );
  }
}

class GestureArea extends StatelessWidget {
  const GestureArea({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(icon), const SizedBox(width: 12), Text(label)],
      ),
    );
  }
}

class ExampleCard extends StatelessWidget {
  const ExampleCard({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
