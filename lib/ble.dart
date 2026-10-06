import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'cpr_metrics.dart';

class EspBle {
  static final Guid serviceUuid = Guid(
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  );

  static final Guid notifyUuid = Guid(
    '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
  );

  static final Guid commandUuid = Guid(
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  );

  BluetoothDevice? device;
  BluetoothCharacteristic? telemetryCharacteristic;
  BluetoothCharacteristic? commandCharacteristic;

  final _telemetryController = StreamController<CprMetrics>.broadcast();

  Stream<CprMetrics> get telemetry => _telemetryController.stream;

  StreamSubscription<List<ScanResult>>? scanSubscription;

  /// Scan for the ESP32.
  Future<BluetoothDevice?> scan() async {
    BluetoothDevice? foundDevice;

    scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName;

        debugPrint('Found: $name (${result.device.remoteId})');

        if (name == 'CPReady') {
          foundDevice = result.device;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withNames: const ['CPReady'],
      timeout: const Duration(seconds: 5),
    );

    await FlutterBluePlus.isScanning
        .where((scanning) => scanning == false)
        .first;

    await scanSubscription?.cancel();
    scanSubscription = null;

    return foundDevice;
  }

  // Connect
  Future<void> connect(BluetoothDevice device) async {
    this.device = device;

    await device.connect(
      license: License.nonprofit,
    );

    debugPrint('Connected to ESP32');

    final services = await device.discoverServices();

    for (final service in services) {
      debugPrint('Service: ${service.uuid}');

      if (service.uuid != serviceUuid) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        debugPrint('Characteristic: ${characteristic.uuid}');

        if (characteristic.uuid == notifyUuid) {
          telemetryCharacteristic = characteristic;
        }

        if (characteristic.uuid == commandUuid) {
          commandCharacteristic = characteristic;
        }
      }
    }

    if (telemetryCharacteristic == null) {
      throw Exception('ESP32 telemetry characteristic not found');
    }

    if (commandCharacteristic == null) {
      throw Exception('ESP32 command characteristic not found');
    }

    debugPrint('ESP32 characteristics found');
  }

  /// Start receiving telemetry notifications.
  Future<void> startTelemetry() async {
    final characteristic = telemetryCharacteristic;

    if (characteristic == null) {
      throw Exception('Not connected to ESP32');
    }

    await characteristic.setNotifyValue(true);

    characteristic.lastValueStream.listen(_onTelemetryChunk);
  }

  void _onTelemetryChunk(List<int> value) {
    try {
      final metrics = CprMetrics.fromBytes(value);
      _telemetryController.add(metrics);
    } catch (error) {
      debugPrint('Telemetry decode failed: $error');
      debugPrint('Raw bytes: $value');
    }
  }

  /// Send a command.
  Future<void> sendCommand(String command) async {
    final characteristic = commandCharacteristic;

    if (characteristic == null) {
      throw Exception('Not connected to ESP32');
    }

    await characteristic.write(
      utf8.encode(command),
    );
  }

  Future<void> disconnect() async {
    await device?.disconnect();

    await _telemetryController.close();

    device = null;
    telemetryCharacteristic = null;
    commandCharacteristic = null;
  }
}
