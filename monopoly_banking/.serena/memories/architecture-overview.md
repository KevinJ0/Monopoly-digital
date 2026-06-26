# Monopoly Banking - Architecture Overview

## Description
Offline P2P Monopoly banking app. Players connect to a central "Bank" device via TCP sockets over Wi-Fi (no internet required). Supports NFC and BLE as alternative P2P transport.

## Roles
- **Bank (Banco)**: Hosts a TCP server on port 8080, manages all player balances, processes transfers. Uses `BancoLogic`.
- **Client (Cliente)**: Connects to the bank via TCP socket, sends transfer requests. Uses `ClienteLogic`.

## Project Structure (lib/)
```
lib/
├── main.dart              # Entry point, initializes Hive, Sound, ErrorTranslator
├── app.dart               # MaterialApp, providers, root routing (splash -> role/wallet)
├── core/
│   └── constants.dart     # Colors, money symbol, initial balance constants
├── models/
│   ├── session_model.dart      # Hive-encrypted session (balance, role, vault, tier)
│   ├── transaction_model.dart  # Hive-encrypted transaction record
│   └── usuario_model.dart      # Legacy bank user model (JSON file based)
├── providers/
│   ├── session_provider.dart       # Session creation/restore/clear, handshake
│   ├── wallet_controller.dart      # Balance ops, vault investment, tier system, haptics
│   ├── stats_provider.dart         # Transaction volume/count tracking
│   └── balance_tween_controller.dart # Animated balance transitions
├── screens/
│   ├── splash_screen.dart          # Animated splash with confetti
│   ├── role_selection_screen.dart  # Role picker (Bank/Client), avatar & color selection
│   ├── bank_screen.dart            # Bank dashboard (player list, transfers)
│   ├── wallet_screen.dart          # Client wallet (balance, vault, chart, history)
│   ├── player_discovery_screen.dart # NFC/BLE discovery UI
│   └── nfc_test_screen.dart        # NFC debug/test screen
├── services/
│   ├── banco_logic.dart            # TCP server (ServerSocket), user management
│   ├── cliente_logic.dart          # TCP client (Socket), auto-reconnect
│   ├── p2p_service.dart            # Unified P2P: NFC first, BLE fallback
│   ├── nfc_service.dart            # NFC reader/writer (HCE)
│   ├── ble_service.dart            # BLE scan/connect/advertise
│   ├── hive_service.dart           # Hive + FlutterSecureStorage init, encryption
│   ├── sound_service.dart          # Sound effects pool
│   ├── voz_service.dart            # Text-to-speech (flutter_tts)
│   ├── biometria_service.dart      # Fingerprint/biometric auth
│   ├── error_translator_service.dart # Maps exceptions to user-friendly messages
│   └── network_service.dart        # Network connectivity check
└── widgets/
    ├── animated_entry.dart         # Staggered fade+slide entry animation
    ├── odometer_widget.dart        # Rolling number counter widget
    ├── premium_dialog.dart         # Tier upgrade celebration dialog
    └── transaction_tile.dart       # Transaction history list tile
```

## State Management
- **Provider** (via `package:provider`) with `MultiProvider` in `MonopolyApp`.
- `WalletController` and `SessionProvider` extend `ChangeNotifier`.
- `BalanceTweenController` is a plain `Provider` (not ChangeNotifier) for animating balance changes.

## Data Flow
1. User picks role on `RoleSelectionScreen` -> `SessionProvider.createSession()` persists to Hive.
2. Client connects to Bank via TCP (`ClienteLogic`).
3. Bank manages all balances in-memory + persists to JSON (`USUARIOS.json`).
4. Client requests transfer -> Bank processes -> broadcasts updated user list.
5. Alternative: NFC/BLE direct P2P via `P2PService` for nearby device transfers.

## Persistence
- **Hive** (encrypted): session data, transaction history.
- **FlutterSecureStorage**: stores the Hive encryption key.
- **JSON file (legacy)**: bank user data via `BancoLogic`.

## Key Dependencies
- `hive` / `hive_flutter` - Local encrypted storage
- `flutter_secure_storage` - Encryption key storage
- `provider` - State management
- `flutter_reactive_ble` - BLE communication
- `nfc_manager` - NFC tag reading/writing
- `uuid` - Transaction IDs
- `encrypt` / `crypto` - Encryption utilities
- `audioplayers` - Sound effects
- `flutter_tts` - Voice announcements
- `local_auth` - Biometric authentication
- `fl_chart` - Balance chart
- `confetti` - Celebrations
- `sqflite` - Available for future use
- `google_generative_ai` - Available for future AI features
