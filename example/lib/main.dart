import 'package:flutter/material.dart';

// ignore: depend_on_referenced_packages
import 'package:session_recorder_flutter/session_recorder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SessionRecorder.init(SessionRecorderConfig(debugLog: true, endpoint: ""));

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const ExampleApp(),
      builder: (context, child) => SessionRecorderWidget(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Example')),
      body: ListView.builder(
        itemCount: 20,
        itemBuilder: (context, index) => ListTile(
          title: Text('Item #$index'),
          subtitle: Text('A subtitle'),
          leading: Container(
            width: 32.0,
            height: 32.0,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing: IconButton(icon: Icon(Icons.add), onPressed: () {}),
        ),
      ),
    );
  }
}
