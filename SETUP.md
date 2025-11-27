# OFFLINK Setup Guide

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / VS Code with Flutter extensions
- Physical Android device (BLE doesn't work on emulators)

## Installation Steps

1. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

2. **Generate Hive adapters:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Connect your Android device:**
   - Enable Developer Options
   - Enable USB Debugging
   - Connect via USB

4. **Run the app:**
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── core/                    # App constants, colors, strings
├── models/                  # Data models (Device, Message)
├── services/
│   ├── communication/      # BLE, Wi-Fi Direct, Connection Manager
│   └── storage/            # Hive message storage
├── providers/              # Riverpod state management
├── screens/                # UI screens
│   ├── splash/
│   ├── auth/
│   ├── home/
│   ├── chat/
│   └── connection/
└── utils/                  # Utilities (logger, permissions)
```

## Important Notes

1. **Permissions**: The app requires Bluetooth, Location, and Nearby Devices permissions. These will be requested on first launch.

2. **Physical Devices**: BLE functionality requires physical Android devices. Emulators won't work.

3. **Wi-Fi Direct**: The Wi-Fi Direct implementation uses platform channels. Native Android code needs to be implemented for full functionality.

4. **Hive Adapters**: After running `build_runner`, the `message_model.g.dart` file will be properly generated.

## Troubleshooting

- **Import errors**: Run `flutter pub get` to install dependencies
- **Hive errors**: Run `flutter pub run build_runner build`
- **BLE not working**: Ensure you're using a physical device, not an emulator
- **Permission denied**: Go to app settings and manually grant permissions

## Next Steps

1. Implement native Wi-Fi Direct code in Android
2. Test BLE communication between two devices
3. Add file sharing functionality
4. Implement group chat features




