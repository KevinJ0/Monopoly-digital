# Monopoly Banking - Code Conventions

## General Style
- Language: **Spanish** for UI strings and comments (app targets Spanish-speaking users).
- All code follows **Dart** conventions (lowerCamelCase for variables/methods, UpperCamelCase for classes).
- Use `const` constructors whenever possible for Flutter widgets.
- Avoid adding comments unless the logic is non-obvious.

## Naming
- Files: `snake_case.dart` (e.g., `role_selection_screen.dart`).
- Classes: `PascalCase` (e.g., `WalletController`).
- Variables/Methods: `camelCase` (e.g., `subtractFunds`, `rawBalance`).
- Constants: `k` prefix + PascalCase (e.g., `kBgDark`, `kGreen`).
- Private members: `_` prefix (e.g., `_session`, `_audioPlayer`).
- Stream controllers: suffix with `Ctrl` (e.g., `_payloadStreamCtrl`).

## UI Pattern
- Use `StatefulWidget` for screens with interactive state; `StatelessWidget` for simple presentational widgets.
- Private widget classes prefixed with `_` (e.g., `_RoleButton`, `_HeaderWidget`).
- Use `WidgetsBindingObserver` for lifecycle-aware widgets.
- Navigation: `Navigator.of(context).push(MaterialPageRoute(...))`.
- Sound feedback: Call `SoundService.playClick()` on button taps.
- Haptic feedback: Use `HapticFeedback.lightImpact()` / `mediumImpact()`.

## State Management
- Providers expose `ValueNotifier<double>` for animated numeric values (e.g., `rawBalance`).
- Use `StreamController.broadcast()` for event streams (e.g., transaction events, tier upgrades).
- Call `notifyListeners()` after mutating state in `ChangeNotifier`.
- Use `context.read<T>()` for one-time reads, `context.watch<T>()` for reactive rebuilds.

## Service Layer
- All services are singletons with `factory` constructor + private `_instance` or static methods.
- Services are initialized in `main.dart` before `runApp()`.
- Error handling: Catch exceptions silently in services (no rethrow), propagate via streams.

## Models
- `fromJson` / `toJson` factory methods for serialization.
- Hive models use `@HiveType` / `@HiveField` annotations with generated adapters.

## Colors & Theming
- Dark theme only. Colors defined in `core/constants.dart`.
- Background: `kBgDark` (0xFF0A0F1E), Cards: `kBgCard` (0xFF111827).
- Primary: `kGreen` (0xFF00C853), Secondary: `kGold` (0xFFFFD600).
- Use `withValues(alpha: ...)` for opacity (not `withOpacity`).

## Assets
- Sound files in `assets/sounds/`: `theme.mp3`, `cash.wav`, `click.wav`.
- App icon in `assets/icon/app_icon.png`.

## Transfers & Currency
- Internal currency symbol: `$` (kMoneySymbol).
- Initial balance: 2000.0 (`kInitialBalance`).
- Pass Go reward: 200.0 (`kPassGoAmount`).
- Balance is `double`, displayed as integer (no decimals).
