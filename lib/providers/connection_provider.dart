import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_model.dart';
import '../services/communication/connection_manager.dart';
import '../utils/logger.dart';
import 'device_provider.dart';

class ConnectionProviderState {
  final ConnectionStateType state;
  final DeviceModel? connectedDevice;
  final ConnectionType connectionType;
  final String? error;

  ConnectionProviderState({
    this.state = ConnectionStateType.disconnected,
    this.connectedDevice,
    this.connectionType = ConnectionType.none,
    this.error,
  });

  ConnectionProviderState copyWith({
    ConnectionStateType? state,
    DeviceModel? connectedDevice,
    ConnectionType? connectionType,
    String? error,
  }) {
    return ConnectionProviderState(
      state: state ?? this.state,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      connectionType: connectionType ?? this.connectionType,
      error: error ?? this.error,
    );
  }
}

enum ConnectionStateType {
  disconnected,
  connecting,
  connected,
  error,
}

class ConnectionNotifier extends StateNotifier<ConnectionProviderState> {
  final ConnectionManager _connectionManager;
  StreamSubscription<ConnectionState>? _connectionSubscription;
  StreamSubscription<String>? _messageSubscription;

  ConnectionNotifier(this._connectionManager) : super(ConnectionProviderState()) {
    _setupListeners();
  }

  void _setupListeners() {
    _connectionSubscription = _connectionManager.connectionState.listen(
      (connectionState) {
        switch (connectionState) {
          case ConnectionState.connected:
            state = state.copyWith(
              state: ConnectionStateType.connected,
              connectedDevice: _connectionManager.connectedDevice,
              connectionType: _connectionManager.currentConnectionType,
              error: null,
            );
            break;
          case ConnectionState.disconnected:
            state = state.copyWith(
              state: ConnectionStateType.disconnected,
              connectedDevice: null,
              connectionType: ConnectionType.none,
              error: null,
            );
            break;
          case ConnectionState.connecting:
            state = state.copyWith(
              state: ConnectionStateType.connecting,
              error: null,
            );
            break;
          case ConnectionState.error:
            state = state.copyWith(
              state: ConnectionStateType.error,
              error: 'Connection error occurred',
            );
            break;
        }
      },
    );
  }

  Future<bool> connectToDevice(DeviceModel device) async {
    try {
      state = state.copyWith(
        state: ConnectionStateType.connecting,
        error: null,
      );

      final connected = await _connectionManager.connectToDevice(device);

      if (connected) {
        state = state.copyWith(
          state: ConnectionStateType.connected,
          connectedDevice: _connectionManager.connectedDevice,
          connectionType: _connectionManager.currentConnectionType,
          error: null,
        );
        Logger.info('Connected to device: ${device.name}');
      } else {
        state = state.copyWith(
          state: ConnectionStateType.error,
          error: 'Failed to connect to device',
        );
      }

      return connected;
    } catch (e) {
      state = state.copyWith(
        state: ConnectionStateType.error,
        error: 'Connection error: ${e.toString()}',
      );
      Logger.error('Error connecting to device', e);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connectionManager.disconnect();
      state = state.copyWith(
        state: ConnectionStateType.disconnected,
        connectedDevice: null,
        connectionType: ConnectionType.none,
        error: null,
      );
      Logger.info('Disconnected from device');
    } catch (e) {
      state = state.copyWith(
        state: ConnectionStateType.error,
        error: 'Disconnect error: ${e.toString()}',
      );
      Logger.error('Error disconnecting', e);
    }
  }

  Future<bool> sendMessage(String message) async {
    try {
      return await _connectionManager.sendMessage(message);
    } catch (e) {
      Logger.error('Error sending message', e);
      return false;
    }
  }

  bool isConnected() {
    return _connectionManager.isConnected();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();
    super.dispose();
  }
}

// Provider for ConnectionNotifier
final connectionProvider = StateNotifierProvider<ConnectionNotifier, ConnectionProviderState>((ref) {
  final connectionManager = ref.watch(connectionManagerProvider);
  return ConnectionNotifier(connectionManager);
});

