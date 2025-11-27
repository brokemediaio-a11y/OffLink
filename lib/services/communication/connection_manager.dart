import 'dart:async';
import '../../models/device_model.dart';
import 'bluetooth_service.dart';
import 'wifi_direct_service.dart';
import '../../utils/logger.dart';

enum ConnectionType {
  ble,
  wifiDirect,
  none,
}

class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  final BluetoothService _bluetoothService = BluetoothService();
  final WifiDirectService _wifiDirectService = WifiDirectService();

  ConnectionType _currentConnectionType = ConnectionType.none;
  DeviceModel? _connectedDevice;

  final _connectionController = StreamController<ConnectionState>.broadcast();
  final _messageController = StreamController<String>.broadcast();

  Stream<ConnectionState> get connectionState => _connectionController.stream;
  Stream<String> get incomingMessages => _messageController.stream;

  ConnectionType get currentConnectionType => _currentConnectionType;
  DeviceModel? get connectedDevice => _connectedDevice;

  // Initialize both services
  Future<bool> initialize() async {
    try {
      final bleInitialized = await _bluetoothService.initialize();
      final wifiInitialized = await _wifiDirectService.initialize();

      // Set up message listeners
      _bluetoothService.incomingMessages.listen((message) {
        _messageController.add(message);
      });

      _wifiDirectService.incomingMessages.listen((message) {
        _messageController.add(message);
      });

      Logger.info('Connection manager initialized (BLE: $bleInitialized, Wi-Fi Direct: $wifiInitialized)');
      return bleInitialized || wifiInitialized;
    } catch (e) {
      Logger.error('Error initializing connection manager', e);
      return false;
    }
  }

  // Start scanning for devices (both BLE and Wi-Fi Direct)
  Future<void> startScan({bool useBle = true, bool useWifiDirect = false}) async {
    try {
      if (useBle) {
        await _bluetoothService.startScan();
      }
      // Wi-Fi Direct is disabled for now - requires native Android implementation
      // if (useWifiDirect) {
      //   await _wifiDirectService.startScan();
      // }
      Logger.info('Device scan started (BLE: $useBle, Wi-Fi Direct: disabled)');
    } catch (e) {
      Logger.error('Error starting device scan', e);
      rethrow;
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    try {
      await _bluetoothService.stopScan();
      // Wi-Fi Direct disabled
      // await _wifiDirectService.stopScan();
      Logger.info('Device scan stopped');
    } catch (e) {
      Logger.error('Error stopping device scan', e);
    }
  }

  // Connect to device (automatically chooses BLE or Wi-Fi Direct)
  Future<bool> connectToDevice(DeviceModel device) async {
    try {
      bool connected = false;

      if (device.type == DeviceType.ble) {
        connected = await _bluetoothService.connectToDevice(device);
        if (connected) {
          _currentConnectionType = ConnectionType.ble;
          _connectedDevice = _bluetoothService.getConnectedDevice();
        }
      } else if (device.type == DeviceType.wifiDirect) {
        connected = await _wifiDirectService.connectToDevice(device);
        if (connected) {
          _currentConnectionType = ConnectionType.wifiDirect;
          _connectedDevice = await _wifiDirectService.getConnectedDevice();
        }
      }

      if (connected && _connectedDevice != null) {
        _connectionController.add(ConnectionState.connected);
        Logger.info('Connected to device: ${device.name}');
      } else {
        _connectionController.add(ConnectionState.disconnected);
        Logger.error('Failed to connect to device: ${device.name}');
      }

      return connected;
    } catch (e) {
      Logger.error('Error connecting to device', e);
      _connectionController.add(ConnectionState.disconnected);
      return false;
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      if (_currentConnectionType == ConnectionType.ble) {
        await _bluetoothService.disconnect();
      } else if (_currentConnectionType == ConnectionType.wifiDirect) {
        await _wifiDirectService.disconnect();
      }

      _currentConnectionType = ConnectionType.none;
      _connectedDevice = null;
      _connectionController.add(ConnectionState.disconnected);
      Logger.info('Disconnected from device');
    } catch (e) {
      Logger.error('Error disconnecting', e);
    }
  }

  // Send message
  Future<bool> sendMessage(String message) async {
    try {
      if (_currentConnectionType == ConnectionType.ble) {
        return await _bluetoothService.sendMessage(message);
      } else if (_currentConnectionType == ConnectionType.wifiDirect) {
        return await _wifiDirectService.sendMessage(message);
      } else {
        Logger.error('Not connected to any device');
        return false;
      }
    } catch (e) {
      Logger.error('Error sending message', e);
      return false;
    }
  }

  // Check if connected
  bool isConnected() {
    if (_currentConnectionType == ConnectionType.ble) {
      return _bluetoothService.isConnected();
    } else if (_currentConnectionType == ConnectionType.wifiDirect) {
      // Wi-Fi Direct connection check is async, so we'll use a cached value
      return _connectedDevice != null;
    }
    return false;
  }

  // Get discovered devices from both services
  Stream<List<DeviceModel>> getDiscoveredDevices() {
    // Combine streams from both services
    return Stream.periodic(const Duration(milliseconds: 500), (_) {
      // This is a simplified approach - in production, you'd want to properly merge streams
      return <DeviceModel>[];
    });
  }

  // Dispose
  void dispose() {
    _bluetoothService.dispose();
    _wifiDirectService.dispose();
    _connectionController.close();
    _messageController.close();
  }
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

