import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/device_model.dart';
import '../../core/constants.dart';
import '../../utils/logger.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<int>>? _messageSubscription;

  final _discoveredDevices = <String, DeviceModel>{};
  final _deviceController = StreamController<List<DeviceModel>>.broadcast();
  final _messageController = StreamController<String>.broadcast();

  Stream<List<DeviceModel>> get discoveredDevices => _deviceController.stream;
  Stream<String> get incomingMessages => _messageController.stream;

  // Initialize Bluetooth
  Future<bool> initialize() async {
    try {
      // Check if Bluetooth is available
      final isAvailable = await FlutterBluePlus.isSupported;
      if (!isAvailable) {
        Logger.warning('Bluetooth is not available');
        return false;
      }

      // Check if Bluetooth is on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        Logger.warning('Bluetooth is not turned on');
        return false;
      }

      Logger.info('Bluetooth service initialized');
      return true;
    } catch (e) {
      Logger.error('Error initializing Bluetooth service', e);
      return false;
    }
  }

  // Start scanning for devices
  Future<void> startScan() async {
    try {
      await initialize();

      _discoveredDevices.clear();
      
      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: AppConstants.bleScanTimeout,
      );

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final device = DeviceModel(
            id: result.device.remoteId.str,
            name: result.device.platformName.isNotEmpty
                ? result.device.platformName
                : 'Unknown Device',
            address: result.device.remoteId.str,
            type: DeviceType.ble,
            rssi: result.rssi,
            lastSeen: DateTime.now(),
          );

          _discoveredDevices[device.id] = device;
          _deviceController.add(_discoveredDevices.values.toList());
        }
      }, onError: (error) {
        Logger.error('Error during BLE scan', error);
      });

      Logger.info('BLE scan started');
    } catch (e) {
      Logger.error('Error starting BLE scan', e);
      rethrow;
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      Logger.info('BLE scan stopped');
    } catch (e) {
      Logger.error('Error stopping BLE scan', e);
    }
  }

  // Connect to a device
  Future<bool> connectToDevice(DeviceModel device) async {
    try {
      final bluetoothDevice = BluetoothDevice.fromId(device.address);

      // Connect to device
      await bluetoothDevice.connect(
        timeout: AppConstants.connectionTimeout,
        autoConnect: false,
      );

      _connectedDevice = bluetoothDevice;

      // Discover services
      final services = await bluetoothDevice.discoverServices();
      
      // Find our service and characteristic
      for (var service in services) {
        if (service.uuid.toString().toUpperCase() ==
            AppConstants.bleServiceUuid.toUpperCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                AppConstants.bleCharacteristicUuid.toUpperCase()) {
              _characteristic = characteristic;

              // Subscribe to notifications
              await characteristic.setNotifyValue(true);
              
              // Listen for incoming messages
              _messageSubscription = characteristic.onValueReceived.listen(
                (value) {
                  final message = String.fromCharCodes(value);
                  _messageController.add(message);
                  Logger.debug('Received message via BLE: $message');
                },
              );

              Logger.info('Connected to device: ${device.name}');
              return true;
            }
          }
        }
      }

      Logger.warning('Service or characteristic not found');
      return false;
    } catch (e) {
      Logger.error('Error connecting to device', e);
      return false;
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      await _messageSubscription?.cancel();
      _messageSubscription = null;
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
        _characteristic = null;
        Logger.info('Disconnected from device');
      }
    } catch (e) {
      Logger.error('Error disconnecting', e);
    }
  }

  // Send message
  Future<bool> sendMessage(String message) async {
    try {
      if (_characteristic == null) {
        Logger.error('Not connected to any device');
        return false;
      }

      final messageBytes = message.codeUnits;
      await _characteristic!.write(messageBytes, withoutResponse: false);
      
      Logger.debug('Message sent via BLE: $message');
      return true;
    } catch (e) {
      Logger.error('Error sending message', e);
      return false;
    }
  }

  // Check if connected
  bool isConnected() {
    return _connectedDevice != null && _characteristic != null;
  }

  // Get connected device
  DeviceModel? getConnectedDevice() {
    if (_connectedDevice == null) return null;
    
    return DeviceModel(
      id: _connectedDevice!.remoteId.str,
      name: _connectedDevice!.platformName.isNotEmpty
          ? _connectedDevice!.platformName
          : 'Connected Device',
      address: _connectedDevice!.remoteId.str,
      type: DeviceType.ble,
      isConnected: true,
    );
  }

  // Dispose
  void dispose() {
    _scanSubscription?.cancel();
    _messageSubscription?.cancel();
    _deviceController.close();
    _messageController.close();
    disconnect();
  }
}

