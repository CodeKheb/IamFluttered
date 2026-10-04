import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class EspBLE {
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

  StreamSubscription<List<ScanResult>>? scanSubscription;

  /// Scan for the ESP32.
  Future<BluetoothDevice?> scan() async {
    BluetoothDevice? foundDevice;

    scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName;

        print('Found: $name (${result.device.remoteId})');

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
            license: License.nonprofit
    );

    print('Connected to ESP32');

    final services = await device.discoverServices();

    for (final service in services) {
      print('Service: ${service.uuid}');

      if (service.uuid != serviceUuid) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        print('Characteristic: ${characteristic.uuid}');

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

    print('ESP32 characteristics found');
  }

  /// Start receiving telemetry notifications.
  Future<void> startTelemetry() async {
    final characteristic = telemetryCharacteristic;

    if (characteristic == null) {
      throw Exception('Not connected to ESP32');
    }

    await characteristic.setNotifyValue(true);

    characteristic.lastValueStream.listen((value) {
      print('Received ${value.length} bytes');

      print('Raw bytes: $value');

      try {
        final text = utf8.decode(value);
        print('As UTF-8: $text');
      } catch (_) {
        print('Packet is binary data');
      }
    });
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

    device = null;
    telemetryCharacteristic = null;
    commandCharacteristic = null;
  }
}
