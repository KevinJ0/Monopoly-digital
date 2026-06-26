# Monopoly Banking - Development Guide

## Requirements
- Flutter SDK >=3.4.0 <4.0.0
- Dart SDK bundled with Flutter
- Android SDK (for Android builds)
- iOS requires Xcode (macOS only)

## Setup
```bash
# Clone and navigate to project
cd monopoly_banking

# Install dependencies
flutter pub get

# Run build_runner for Hive adapters (if models change)
dart run build_runner build --delete-conflicting-outputs

# Generate launcher icons (if icon changes)
dart run flutter_launcher_icons
```

## Running
```bash
# Run on connected device / emulator
flutter run

# Run with specific device
flutter devices
flutter run -d <device_id>

# Build APK
flutter build apk

# Build App Bundle
flutter build appbundle
```

## Testing
- No dedicated test files yet. Tests should go in `test/` directory.
- Use `flutter test` to run all tests.

## Key Flows to Test Manually

### Bank Mode
1. Launch app -> Tap "SER EL BANCO"
2. Bank screen shows. Wait for clients to connect.
3. Clients appear in player list.
4. Initiate transfer: select player, enter amount, confirm.

### Client Mode
1. Launch app -> Select avatar/color -> "ENTRAR COMO CLIENTE"
2. Wallet screen shows with $2000 initial balance.
3. Transfer: tap player tile, enter amount, confirm.
4. Balance updates in real-time.

### Pass Go
1. Tap "PASS GO" button on wallet screen.
2. Balance increases by $200.
3. Sound + haptic feedback plays.

### Vault Investment
1. Tap "VAULT" on wallet.
2. Enter amount and number of GO passes (1-5).
3. Each "PASS GO" generates interest.
4. Withdraw early (80% penalty) or after target passes (full amount + interest).

### NFC/BLE P2P
1. Two devices nearby: one selects "Receive" flow, other "Send".
2. NFC: Tap devices together.
3. BLE: Auto-discovers and connects.

## Troubleshooting
- **Hive decryption errors**: Delete app data or reinstall.
- **TCP connection refused**: Ensure bank app is running first, client connects to correct IP.
- **NFC not working**: Enable NFC in device settings. Some emulators lack NFC support.
- **BLE issues**: Android requires location permission for BLE scanning.
- **Build errors**: Run `flutter clean` then `flutter pub get`.
