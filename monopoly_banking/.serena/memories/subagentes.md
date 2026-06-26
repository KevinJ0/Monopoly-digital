# Subagentes del proyecto monopoly_banking

Se crearon 5 subagentes (modos de Serena) para trabajar con el proyecto:

| Modo | Propósito | Archivos clave |
|---|---|---|
| `flutter-runner` | Build, run, test, deploy | pubspec.yaml, Android/iOS |
| `p2p-networking` | BLE, NFC, TCP sockets | p2p_service, ble_service, nfc_service, banco_logic, cliente_logic |
| `ui-designer` | Pantallas, widgets, animaciones | screens/, widgets/, constants.dart |
| `data-layer` | Hive, modelos, persistencia | models/, hive_service, session_provider |
| `bank-logic` | Transferencias, vault, wallet | wallet_controller, banco_logic, session_model |

## Cómo usarlos
- Activar un subagente específico: `--add-mode flutter-runner` al iniciar Serena
- Activar múltiples: `--add-mode flutter-runner --add-mode ui-designer`
- Ver todos disponibles: `serena mode list`

## Modos base (siempre activos)
- `interactive` - Conversación general
- `editing` - Edición de código
