import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../utils/logger.dart';

class DeviceStorage {
  static const String _deviceIdKey = 'device_id';
  static const String _displayNameKey = 'display_name';
  static const String _deviceBoxName = 'device_preferences';
  static Box? _deviceBox;

  static Future<void> init() async {
    try {
      _deviceBox = await Hive.openBox(_deviceBoxName);
      Logger.info('Device storage initialized');
    } catch (e) {
      Logger.error('Error initializing device storage', e);
      rethrow;
    }
  }

  /// Get the persistent device ID, or generate and store a new one if it doesn't exist
  static String getDeviceId() {
    try {
      if (_deviceBox == null) {
        Logger.warning('Device storage not initialized, generating new UUID');
        return _generateAndStoreDeviceId();
      }

      final storedId = _deviceBox!.get(_deviceIdKey) as String?;
      
      if (storedId != null && storedId.isNotEmpty) {
        Logger.info('Retrieved persistent device ID: $storedId');
        return storedId;
      }

      // No stored ID, generate and store a new one
      return _generateAndStoreDeviceId();
    } catch (e) {
      Logger.error('Error getting device ID', e);
      // Fallback: generate a new one (but don't store it if storage failed)
      return const Uuid().v4();
    }
  }

  static String _generateAndStoreDeviceId() {
    try {
      final newId = const Uuid().v4();
      if (_deviceBox != null) {
        _deviceBox!.put(_deviceIdKey, newId);
        Logger.info('Generated and stored new device ID: $newId');
      } else {
        Logger.warning('Device storage not initialized, cannot store new UUID');
      }
      return newId;
    } catch (e) {
      Logger.error('Error generating device ID', e);
      return const Uuid().v4();
    }
  }

  /// Clear the stored device ID (for testing/reset purposes)
  static Future<void> clearDeviceId() async {
    try {
      await _deviceBox?.delete(_deviceIdKey);
      Logger.info('Device ID cleared');
    } catch (e) {
      Logger.error('Error clearing device ID', e);
    }
  }

  /// Get the user's display name, or return null if not set
  static String? getDisplayName() {
    try {
      return _deviceBox?.get(_displayNameKey) as String?;
    } catch (e) {
      Logger.error('Error getting display name', e);
      return null;
    }
  }

  /// Set the user's display name
  static Future<void> setDisplayName(String name) async {
    try {
      await _deviceBox?.put(_displayNameKey, name);
      Logger.info('Display name set to: $name');
    } catch (e) {
      Logger.error('Error setting display name', e);
    }
  }

  /// Get display name for a device UUID (for storing other devices' names)
  static String? getDeviceDisplayName(String deviceId) {
    try {
      return _deviceBox?.get('device_name_$deviceId') as String?;
    } catch (e) {
      return null;
    }
  }

  /// Set display name for a device UUID (for storing other devices' names)
  static Future<void> setDeviceDisplayName(String deviceId, String name) async {
    try {
      await _deviceBox?.put('device_name_$deviceId', name);
      Logger.info('Device display name set: $deviceId -> $name');
    } catch (e) {
      Logger.error('Error setting device display name', e);
    }
  }
}

