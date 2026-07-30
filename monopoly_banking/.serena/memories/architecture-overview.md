# Money Manager - Architecture Overview

## Description
Offline P2P Money Manager app. Players connect to a central "Bank" device via TCP sockets over Wi-Fi (no internet required). Supports NFC and BLE as alternative P2P transport.

## Roles
- **Bank (Banco)**: Hosts a TCP server on port 8080, manages all player balances, processes transfers. Uses `BancoLogic`.
- **Client (Cliente)**: Connects to the bank via TCP socket, sends transfer requests. Uses `ClienteLogic`.

## Project Structure (lib/)
```
lib/
â”œâ”€â”€ main.dart              # Entry point, initializes Hive, Sound, ErrorTranslator
â”œâ”€â”€ app.dart               # MaterialApp, providers, root routing (splash -> role/wallet)
â”œâ”€â”€ core/
â”‚   â””â”€â”€ constants.dart     # Colors, money symbol, initial balance constants
â”œâ”€â”€ models/
â”‚   â”œâ”€â”€ session_model.dart      # Hive-encrypted session (balance, role, vault, tier)
â”‚   â”œâ”€â”€ transaction_model.dart  # Hive-encrypted transaction record
â”‚   â””â”€â”€ usuario_model.dart      # Legacy bank user model (JSON file based)
â”œâ”€â”€ providers/
â”‚   â”œâ”€â”€ session_provider.dart       # Session creation/restore/clear, handshake
â”‚   â”œâ”€â”€ wallet_controller.dart      # Balance ops, vault investment, tier system, haptics
â”‚   â”œâ”€â”€ stats_provider.dart         # Transaction volume/count tracking
â”‚   â””â”€â”€ balance_tween_controller.dart # Animated balance transitions
â”œâ”€â”€ screens/
â”‚   â”œâ”€â”€ splash_screen.dart          # Animated splash with confetti
â”‚   â”œâ”€â”€ role_selection_screen.dart  # Role picker (Bank/Client), avatar & color selection
â”‚   â”œâ”€â”€ bank_screen.dart            # Bank dashboard (player list, transfers)
â”‚   â”œâ”€â”€ wallet_screen.dart          # Client wallet (balance, vault, chart, history)
â”‚   â”œâ”€â”€ player_discovery_screen.dart # NFC/BLE discovery UI
â”‚   â””â”€â”€ nfc_test_screen.dart        # NFC debug/test screen
â”œâ”€â”€ services/
â”‚   â”œâ”€â”€ banco_logic.dart            # TCP server (ServerSocket), user management
â”‚   â”œâ”€â”€ cliente_logic.dart          # TCP client (Socket), auto-reconnect
â”‚   â”œâ”€â”€ p2p_service.dart            # Unified P2P: NFC first, BLE fallback
â”‚   â”œâ”€â”€ nfc_service.dart            # NFC reader/writer (HCE)
â”‚   â”œâ”€â”€ ble_service.dart            # BLE scan/connect/advertise
â”‚   â”œâ”€â”€ hive_service.dart           # Hive + FlutterSecureStorage init, encryption
â”‚   â”œâ”€â”€ sound_service.dart          # Sound effects pool
â”‚   â”œâ”€â”€ voz_service.dart            # Text-to-speech (flutter_tts)
â”‚   â”œâ”€â”€ biometria_service.dart      # Fingerprint/biometric auth
â”‚   â”œâ”€â”€ error_translator_service.dart # Maps exceptions to user-friendly messages
â”‚   â””â”€â”€ network_service.dart        # Network connectivity check
â””â”€â”€ widgets/
    â”œâ”€â”€ animated_entry.dart         # Staggered fade+slide entry animation
    â”œâ”€â”€ odometer_widget.dart        # Rolling number counter widget
    â”œâ”€â”€ premium_dialog.dart         # Tier upgrade celebration dialog
    â””â”€â”€ transaction_tile.dart       # Transaction history list tile
```

## State Management
- **Provider** (via `package:provider`) with `MultiProvider` in `Money ManagerApp`.
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

