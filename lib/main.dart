import 'dart:async';

import 'package:flutter/material.dart';

import 'ble.dart';
import 'cpr_metrics.dart';

void main() {
  runApp(const CpReadyApp());
}

class CpReadyApp extends StatelessWidget {
  const CpReadyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CPReady',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const CpReadyHomePage(),
    );
  }
}

enum AppStage {
  idle,
  scanning,
  connecting,
  connected,
  calibrating,
  ready,
  active,
  sessionComplete,
  error,
}

class CpReadyHomePage extends StatefulWidget {
  const CpReadyHomePage({super.key});

  @override
  State<CpReadyHomePage> createState() => _CpReadyHomePageState();
}

class _CpReadyHomePageState extends State<CpReadyHomePage> {
  final ble = EspBle();

  AppStage stage = AppStage.idle;
  String error = '';

  StreamSubscription<CprMetrics>? _telemetrySubscription;

  CprMetrics? lastMetrics;
  CprMetrics? summaryMetrics;

  Future<void> connect() async {
    setState(() {
      stage = AppStage.scanning;
      error = '';
    });

    try {
      final device = await ble.scan();

      if (device == null) {
        setState(() {
          stage = AppStage.error;
          error = 'Device not found';
        });
        return;
      }

      setState(() {
        stage = AppStage.connecting;
      });

      await ble.connect(device);
      await ble.startTelemetry();

      await _telemetrySubscription?.cancel();
      _telemetrySubscription = ble.telemetry.listen((metrics) {
        if (!mounted) return;

        setState(() {
          lastMetrics = metrics;

          switch (metrics.packetType) {
            case 2:
              stage = AppStage.calibrating;
              break;
            case 3:
              stage = AppStage.ready;
              break;
            case 4:
              summaryMetrics = metrics;
              stage = AppStage.sessionComplete;
              break;
            case 5:
              stage = AppStage.error;
              error = 'Firmware reported an error';
              break;
            default:
              if (stage == AppStage.connected ||
                  stage == AppStage.ready ||
                  stage == AppStage.calibrating) {
                stage = AppStage.active;
              }
          }
        });
      });

      setState(() {
        stage = AppStage.connected;
      });
    } catch (e) {
      setState(() {
        stage = AppStage.error;
        error = 'Connection failed: $e';
      });
    }
  }

  Future<void> sendCommand(String command) async {
    try {
      await ble.sendCommand(command);
    } catch (e) {
      setState(() {
        stage = AppStage.error;
        error = 'Command failed: $e';
      });
    }
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CPReady')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StageCard(
                stage: stage,
                error: error,
              ),

              const SizedBox(height: 16),

              if (lastMetrics != null) ...<Widget>[
                _LiveMetricsCard(
                  metrics: lastMetrics!,
                  summary: summaryMetrics,
                ),
              ],

              const Spacer(),

              _CommandRow(
                stage: stage,
                onStart: () => sendCommand('START'),
                onPause: () => sendCommand('PAUSE'),
                onStop: () => sendCommand('STOP'),
                onGetResults: () => sendCommand('GET_RESULTS'),
              ),

              const SizedBox(height: 16),

              _ConnectButton(
                stage: stage,
                onConnect: connect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final AppStage stage;
  final VoidCallback onConnect;

  const _ConnectButton({
    required this.stage,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final busy = stage == AppStage.scanning || stage == AppStage.connecting;

    final String label;
    if (busy) {
      label = stage == AppStage.scanning ? 'Scanning...' : 'Connecting...';
    } else if (stage == AppStage.idle || stage == AppStage.error) {
      label = 'Connect to CPReady';
    } else {
      label = 'Connect to CPReady (reconnect)';
    }

    return ElevatedButton(
      onPressed: busy ? null : onConnect,
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}

class _StageCard extends StatelessWidget {
  final AppStage stage;
  final String error;

  const _StageCard({
    required this.stage,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final label = _stageLabel(stage);

    Color color;
    switch (stage) {
      case AppStage.idle:
      case AppStage.scanning:
        color = Colors.blue;
      case AppStage.connecting:
        color = Colors.orange;
      case AppStage.connected:
        color = Colors.cyan;
      case AppStage.calibrating:
        color = Colors.purple;
      case AppStage.ready:
        color = Colors.green;
      case AppStage.active:
        color = Colors.indigo;
      case AppStage.sessionComplete:
        color = Colors.teal;
      case AppStage.error:
        color = Colors.red;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _stageDescription(stage, error),
              style: Theme.of(context).textTheme.bodyMedium?.apply(
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _stageLabel(AppStage stage) {
    switch (stage) {
      case AppStage.idle:
        return 'Idle';
      case AppStage.scanning:
        return 'Scanning';
      case AppStage.connecting:
        return 'Connecting';
      case AppStage.connected:
        return 'Connected';
      case AppStage.calibrating:
        return 'Calibrating';
      case AppStage.ready:
        return 'Ready';
      case AppStage.active:
        return 'Active';
      case AppStage.sessionComplete:
        return 'Session Complete';
      case AppStage.error:
        return 'Error';
    }
  }

  static String _stageDescription(AppStage stage, String error) {
    if (stage == AppStage.error && error.isNotEmpty) {
      return error;
    }

    switch (stage) {
      case AppStage.idle:
        return 'Waiting to connect to CPReady.';
      case AppStage.scanning:
        return 'Scanning for CPReady BLE device.';
      case AppStage.connecting:
        return 'Connecting and discovering services.';
      case AppStage.connected:
        return 'Connected to CPReady. Send START to begin.';
      case AppStage.calibrating:
        return 'Baseline calibration in progress.';
      case AppStage.ready:
        return 'Calibration complete. Begin compressions.';
      case AppStage.active:
        return 'Compression session active.';
      case AppStage.sessionComplete:
        return 'Session summary received.';
      case AppStage.error:
        return 'Something went wrong.';
    }
  }
}

class _LiveMetricsCard extends StatelessWidget {
  final CprMetrics metrics;
  final CprMetrics? summary;

  const _LiveMetricsCard({
    required this.metrics,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final useSummary = metrics.packetType == 4;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              useSummary ? 'Session Summary' : 'Live Metrics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _MetricRow('Type', packetTypeLabel(metrics.packetType)),
            _MetricRow('Rate', '${metrics.rateCpm} cpm'),
            _MetricRow('Depth', '${metrics.depthCm.toStringAsFixed(2)} cm / ${metrics.depthMm.toStringAsFixed(1)} mm'),
            _MetricRow(
              'Recoil',
              useSummary
                  ? '${metrics.recoilPercentage}%'
                  : (metrics.recoilComplete ? 'Full' : 'Leaning'),
            ),
            _MetricRow('CCF', '${metrics.ccfPercent}%'),
            _MetricRow(
              'Audio Cue',
              audioPromptText(metrics.audioPromptCode),
            ),
            _MetricRow(
              'Compressions',
              useSummary
                  ? '${metrics.totalCompressions}'
                  : '${metrics.totalCompressions}',
            ),
            _MetricRow('Elapsed', '${metrics.elapsedSeconds}s'),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  final AppStage stage;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onGetResults;

  const _CommandRow({
    required this.stage,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    required this.onGetResults,
  });

  @override
  Widget build(BuildContext context) {
    final connected = stage == AppStage.connected ||
        stage == AppStage.ready ||
        stage == AppStage.calibrating ||
        stage == AppStage.active ||
        stage == AppStage.sessionComplete;

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton(
          onPressed: connected ? onStart : null,
          child: const Text('START'),
        ),
        ElevatedButton(
          onPressed: connected ? onPause : null,
          child: const Text('PAUSE'),
        ),
        ElevatedButton(
          onPressed: connected ? onStop : null,
          child: const Text('STOP'),
        ),
        OutlinedButton(
          onPressed: connected ? onGetResults : null,
          child: const Text('GET RESULTS'),
        ),
      ],
    );
  }
}
