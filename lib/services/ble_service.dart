import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  static BleService? _instance;
  static BleService get instance => _instance ??= BleService._();
  BleService._();

  // -- Must match ESP32 firmware exactly --
  static const String deviceName = 'Aanchal';
  static final Uuid serviceUuid =
      Uuid.parse('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final Uuid characteristicUuid =
      Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a8');
  // ---------------------------------------

  final _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectSub;
  StreamSubscription<List<int>>? _notifySub;

  String? _deviceId;
  bool _connected = false;
  bool _scanning = false;
  Function? _onSOSTrigger;

  bool get isConnected => _connected;

  Future<void> start({required Function onSOS}) async {
    _onSOSTrigger = onSOS;

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final scanStatus = results[Permission.bluetoothScan];
    final connectStatus = results[Permission.bluetoothConnect];
    final requiredDenied = [scanStatus, connectStatus].any(
      (s) => s == null || s.isDenied || s.isPermanentlyDenied,
    );
    if (requiredDenied) {
      debugPrint(
        '[BLE] Permissions denied -- bluetoothScan=$scanStatus '
        'bluetoothConnect=$connectStatus',
      );
      return;
    }

    _startScan();
  }

  void _startScan() {
    if (_scanning || _connected) return;
    _scanning = true;
    debugPrint('[BLE] Scanning for $deviceName...');

    _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
      (device) {
        if (device.name == deviceName && !_connected) {
          debugPrint('[BLE] Found ${device.id}');
          _scanning = false;
          _scanSub?.cancel();
          _connect(device.id);
        }
      },
      onError: (e) {
        debugPrint('[BLE] Scan error: $e');
        _scanning = false;
        Future.delayed(const Duration(seconds: 5), _startScan);
      },
    );
  }

  void _connect(String deviceId) {
    _deviceId = deviceId;
    debugPrint('[BLE] Connecting...');

    _connectSub?.cancel();
    _connectSub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            _connected = true;
            debugPrint('[BLE] Connected to Aanchal button');
            _subscribeNotifications(deviceId);
            break;
          case DeviceConnectionState.disconnected:
            _connected = false;
            _notifySub?.cancel();
            debugPrint('[BLE] Disconnected from $_deviceId -- will rescan');
            Future.delayed(const Duration(seconds: 3), _startScan);
            break;
          default:
            break;
        }
      },
      onError: (e) {
        debugPrint('[BLE] Connect error: $e');
        _connected = false;
        Future.delayed(const Duration(seconds: 5), _startScan);
      },
    );
  }

  void _subscribeNotifications(String deviceId) {
    final char = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    _notifySub?.cancel();
    _notifySub = _ble.subscribeToCharacteristic(char).listen(
      (bytes) {
        final value = String.fromCharCodes(bytes);
        debugPrint('[BLE] Received: $value');
        if (value.trim() == 'SOS') {
          debugPrint('[BLE] Hardware SOS trigger!');
          _onSOSTrigger?.call();
        }
      },
      onError: (e) => debugPrint('[BLE] Notify error: $e'),
    );
  }

  void stop() {
    _scanSub?.cancel();
    _connectSub?.cancel();
    _notifySub?.cancel();
    if (_deviceId != null) {
      debugPrint('[BLE] Closing connection to $_deviceId');
    }
    _deviceId = null;
    _connected = false;
    _scanning = false;
    debugPrint('[BLE] Stopped');
  }
}
