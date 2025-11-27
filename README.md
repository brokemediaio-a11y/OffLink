# OFFLINK - Offline Peer-to-Peer Communication App

A Flutter mobile application that enables device-to-device messaging and file sharing without internet or cellular signals using Bluetooth Low Energy (BLE) and Wi-Fi Direct.

## Features (Phase 1 - 40% Implementation)

- ✅ Device discovery (scan for nearby devices)
- ✅ Connect to selected device
- ✅ Two-way messaging system
- ✅ Send and receive text messages offline
- ✅ Message persistence (store locally)
- ✅ Basic UI screens
- ✅ Message delivery status (sent, delivered)

## Technology Stack

- **Framework**: Flutter
- **State Management**: Riverpod
- **Local Storage**: Hive
- **Communication**: 
  - Bluetooth Low Energy (BLE) via `flutter_blue_plus`
  - Wi-Fi Direct (via platform channels)

## Project Structure

```
/lib
  /core              # Constants, colors, strings
  /models            # Data models
  /services
    /communication   # BLE, Wi-Fi Direct, connection manager
    /storage         # Message storage
  /providers         # Riverpod state management
  /screens           # UI screens
  /utils             # Utilities (logger, permissions)
```

## Setup Instructions

1. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

2. **Generate Hive adapters:**
   ```bash
   flutter pub run build_runner build
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

## Required Permissions

The app requires the following permissions:
- Bluetooth (for BLE communication)
- Location (required for Bluetooth scanning on Android)
- Nearby Devices (for Wi-Fi Direct on Android 12+)

## Android Configuration

The app is configured for Android with:
- Minimum SDK: 21
- Target SDK: 34
- All necessary permissions in AndroidManifest.xml

## Notes

- The app must run on physical Android devices (not emulators) for BLE functionality
- Wi-Fi Direct implementation requires native Android code (platform channels)
- The app works in airplane mode (no internet required)

## Future Enhancements

- Group chat creation
- File sharing
- Offline maps
- Emergency broadcast mode
- Mesh networking support




