# Subagentes del proyecto money_manager

Se crearon 5 subagentes (modos de Serena) para trabajar con el proyecto:

| Modo | PropÃ³sito | Archivos clave |
|---|---|---|
| `flutter-runner` | Build, run, test, deploy | pubspec.yaml, Android/iOS |
| `p2p-networking` | BLE, NFC, TCP sockets | p2p_service, ble_service, nfc_service, banco_logic, cliente_logic |
| `ui-designer` | Pantallas, widgets, animaciones | screens/, widgets/, constants.dart |
| `data-layer` | Hive, modelos, persistencia | models/, hive_service, session_provider |
| `bank-logic` | Transferencias, vault, wallet | wallet_controller, banco_logic, session_model |

## CÃ³mo usarlos
- Activar un subagente especÃ­fico: `--add-mode flutter-runner` al iniciar Serena
- Activar mÃºltiples: `--add-mode flutter-runner --add-mode ui-designer`
- Ver todos disponibles: `serena mode list`

## Modos base (siempre activos)
- `interactive` - ConversaciÃ³n general
- `editing` - EdiciÃ³n de cÃ³digo

