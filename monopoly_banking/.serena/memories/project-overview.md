# Monopoly Banking - Project Overview

## What is this?
A Flutter-based **Monopoly banking app** for playing the board game with digital money. Works **offline** (no internet needed) using:
- **TCP sockets over Wi-Fi** (primary): Bank hosts server, clients connect via local IP
- **NFC** (alternative): Tap phones for direct P2P transfers
- **BLE** (fallback): Bluetooth Low Energy for nearby device discovery

## Audience
Spanish-speaking Monopoly players. All UI text and voice announcements are in Spanish.

## Key Features
- Bank mode: Manage all player balances, approve transfers, broadcast state
- Client wallet: View balance, send money, "Pass Go" button, vault investment with interest
- Vault system: Invest money for interest over N passes of GO (1-5 passes, 5-15% interest)
- Card tiers: Standard ($0) -> Gold ($4k) -> Platinum ($8k) -> Black ($15k)
- Transaction history with balance chart (fl_chart)
- Animated odometer balance display
- Sound effects (cash, clicks) + background music
- Text-to-speech voice announcements
- Biometric auth for large transfers (>$5000)
- NFC/BLE device-to-device handshake for initial balance transfer
- Encrypted local storage (Hive + AES)
- Confetti celebration on tier upgrades

## Quick Commands
- `flutter run` - Launch app
- `flutter build apk` - Build APK
- `dart run build_runner build --delete-conflicting-outputs` - Regenerate Hive adapters
- `flutter clean && flutter pub get` - Reset dependencies

## Default IP for Bank
The bank server binds to `0.0.0.0:8080`. Clients default to `192.168.43.1:8080` (can be changed in `cliente_logic.dart`).
