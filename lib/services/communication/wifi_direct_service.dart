import 'dart:async';
import 'package:flutter/services.dart';
import '../../models/device_model.dart';
import '../../utils/logger.dart';

class WifiDirectService {
  static final WifiDirectService _instance = WifiDirectService._internal();
  factory WifiDirectService() => _instance;
  WifiDirectService._internal();

  static const MethodChannel _channel = MethodChannel('com.offlink.wifi_direct');
  
  final _discoveredDevices = <String, DeviceModel>{};
  final _deviceController = StreamController<List<DeviceModel>>.broadcast();
  final _messageController = StreamController<String>.broadcast();

  Stream<List<DeviceModel>> get discoveredDevices => _deviceController.stream;
  Stream<String> get incomingMessages => _messageController.stream;

  bool _isInitialized = false;
  bool _isScanning = false;

  // Initialize Wi-Fi Direct
  Future<bool> initialize() async {
    try {
      if (_isInitialized) return true;

      // Wi-Fi Direct requires native Android implementation
      // For now, return false to indicate it's not available
      Logger.warning('Wi-Fi Direct is not implemented - requires native Android code');
      return false;
      
      // Uncomment when native code is implemented:
      // // Set up message handler for incoming messages
      // _channel.setMethodCallHandler(_handleMethodCall);
      // final result = await _channel.invokeMethod<bool>('initialize');
      // _isInitialized = result ?? false;
      // return _isInitialized;
    } catch (e) {
      Logger.error('Error initializing Wi-Fi Direct service', e);
      return false;
    }
  }

  // Handle method calls from native side
  Future<void> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onDeviceFound':
          final deviceData = call.arguments as Map;
          final device = DeviceModel(
            id: deviceData['address'] as String,
            name: deviceData['name'] as String? ?? 'Unknown Device',
            address: deviceData['address'] as String,
            type: DeviceType.wifiDirect,
            rssi: deviceData['rssi'] as int? ?? 0,
            lastSeen: DateTime.now(),
          );
          _discoveredDevices[device.id] = device;
          _deviceController.add(_discoveredDevices.values.toList());
          break;

        case 'onMessageReceived':
          final message = call.arguments as String;
          _messageController.add(message);
          Logger.debug('Received message via Wi-Fi Direct: $message');
          break;

        case 'onConnectionChanged':
          final isConnected = call.arguments as bool;
          Logger.info('Wi-Fi Direct connection changed: $isConnected');
          break;

        default:
          Logger.warning('Unknown method call: ${call.method}');
      }
    } catch (e) {
      Logger.error('Error handling method call', e);
    }
  }

  // Start scanning for devices
  Future<void> startScan() async {
    try {
      // Wi-Fi Direct is not implemented - requires native Android code
      Logger.warning('Wi-Fi Direct scanning is not available - requires native implementation');
      _isScanning = false;
      return;
      
      // Uncomment when native code is implemented:
      // if (!_isInitialized) {
      //   await initialize();
      // }
      // if (_isScanning) {
      //   Logger.warning('Scan already in progress');
      //   return;
      // }
      // _discoveredDevices.clear();
      // _isScanning = true;
      // await _channel.invokeMethod('startScan');
      // Logger.info('Wi-Fi Direct scan started');
    } catch (e) {
      Logger.error('Error starting Wi-Fi Direct scan', e);
      _isScanning = false;
      // Don't rethrow - fail silently since it's not implemented
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    try {
      if (!_isScanning) return;

      await _channel.invokeMethod('stopScan');
      _isScanning = false;
      Logger.info('Wi-Fi Direct scan stopped');
    } catch (e) {
      Logger.error('Error stopping Wi-Fi Direct scan', e);
    }
  }

  // Connect to a device
  Future<bool> connectToDevice(DeviceModel device) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      final result = await _channel.invokeMethod<bool>(
        'connectToDevice',
        {
          'address': device.address,
          'name': device.name,
        },
      );

      if (result ?? false) {
        Logger.info('Connected to device via Wi-Fi Direct: ${device.name}');
      } else {
        Logger.error('Failed to connect to device: ${device.name}');
      }

      return result ?? false;
    } catch (e) {
      Logger.error('Error connecting to device', e);
      return false;
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      Logger.info('Disconnected from Wi-Fi Direct device');
    } catch (e) {
      Logger.error('Error disconnecting', e);
    }
  }

  // Send message
  Future<bool> sendMessage(String message) async {
    try {
      if (!_isInitialized) {
        Logger.error('Wi-Fi Direct not initialized');
        return false;
      }

      final result = await _channel.invokeMethod<bool>(
        'sendMessage',
        {'message': message},
      );

      if (result ?? false) {
        Logger.debug('Message sent via Wi-Fi Direct: $message');
      } else {
        Logger.error('Failed to send message via Wi-Fi Direct');
      }

      return result ?? false;
    } catch (e) {
      Logger.error('Error sending message', e);
      return false;
    }
  }

  // Check if connected
  Future<bool> isConnected() async {
    try {
      final result = await _channel.invokeMethod<bool>('isConnected');
      return result ?? false;
    } catch (e) {
      Logger.error('Error checking connection status', e);
      return false;
    }
  }

  // Get connected device
  Future<DeviceModel?> getConnectedDevice() async {
    try {
      final deviceData = await _channel.invokeMethod<Map>('getConnectedDevice');
      if (deviceData == null) return null;

      return DeviceModel(
        id: deviceData['address'] as String,
        name: deviceData['name'] as String? ?? 'Connected Device',
        address: deviceData['address'] as String,
        type: DeviceType.wifiDirect,
        isConnected: true,
      );
    } catch (e) {
      Logger.error('Error getting connected device', e);
      return null;
    }
  }

  // Dispose
  void dispose() {
    _deviceController.close();
    _messageController.close();
    disconnect();
  }
}

