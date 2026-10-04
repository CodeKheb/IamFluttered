import 'package:iamfluttered/ble.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ble = EspBLE();

  String status = 'Disconnected';

  Future<void> connect() async {
    setState(() {
      status = 'Scanning';
    });

    try {
      final device = await ble.scan();

      if (device == null) {
        setState(() {
          status = 'Not Found';
        });
        return;
      }

      setState(() {
        status = 'Connecting...';
      });

      await ble.connect(device);
      await ble.startTelemetry();

      setState(() {
        status = 'Connected';
      });
    } catch (e) {
      setState(() {
        status = 'Error $e';
      });
      print(e);
    }
  }

  @override
  void dispose() {
    ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CPReady')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(status),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () async {
                await ble.sendCommand('GET_RESULTS');
              },
              child: const Text('GET RESULTS'),
            ),

            ElevatedButton(
              onPressed: connect,
              child: const Text('Connect to CPReady'),
            ),
          ],
        ),
      ),
    );
  }
}
