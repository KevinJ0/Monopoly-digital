import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:money_manager/core/constants.dart';
import 'package:money_manager/services/app_audit_logger.dart';
import 'package:money_manager/services/notification_service.dart';
import 'package:money_manager/core/game_transitions.dart';

// â”€â”€â”€ Modelo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

enum ErrorSeverity { info, warning, error, critical }

class FriendlyError {
  final String message;
  final ErrorSeverity severity;
  const FriendlyError({required this.message, required this.severity});
}

// â”€â”€â”€ Servicio principal â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class ErrorTranslatorService {
  static final ErrorTranslatorService _instance = ErrorTranslatorService._();
  factory ErrorTranslatorService() => _instance;
  ErrorTranslatorService._();

  final Map<String, FriendlyError> _cache = {};
  GenerativeModel? _model;

  // âš ï¸ Pon tu API key de Google AI Studio aquí:
  // https://aistudio.google.com/app/apikey
  static const _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // â”€â”€ Init â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> init() async {
    if (_apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.3,
          maxOutputTokens: 200,
        ),
      );
    }
  }

  // â”€â”€ API pública â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Traduce un error técnico a lenguaje humano.
  /// Primero busca en caché SQLite; si no existe, llama a Gemini y lo guarda.
  /// También vuelca el error original al log de auditoría.
  Future<FriendlyError> translate(dynamic error, [StackTrace? stack]) async {
    final raw = error.toString();
    final key = _normalizeAndHash(raw);

    // 0. Guardar en log de auditoría global (sin bloquear)
    AppAuditLogger.instance.error(
      'ERROR_TRANSLATOR',
      error,
      stack: stack,
      data: {'cache_key': key},
    );

    // 1. Buscar en caché
    final cached = await _lookup(key);
    if (cached != null) return cached;

    // 2. Pedir a Gemini
    final friendly = await _askAI(raw, stack);

    // 3. Guardar para la próxima vez
    await _store(key, raw, friendly);

    return friendly;
  }

  // â”€â”€ Normalización â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Elimina partes dinámicas (direcciones de memoria, timestamps, IDs)
  /// para que errores equivalentes compartan la misma key.
  String _normalizeAndHash(String raw) {
    var normalized = raw
        .replaceAll(RegExp(r'0x[0-9a-fA-F]+'), '0x\u2026')
        .replaceAll(RegExp(r'#\d+'), '#\u2026')
        .replaceAll(RegExp(r'\d{10,}'), '\u2026')
        .replaceAll(RegExp(r"Instance of '[^']+'"), 'Instance')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    final bytes = utf8.encode(normalized);
    return sha256.convert(bytes).toString();
  }

  // â”€â”€ Caché en memoria â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<FriendlyError?> _lookup(String key) async {
    return _cache[key];
  }

  Future<void> _store(String key, String raw, FriendlyError friendly) async {
    _cache[key] = friendly;
  }

  // â”€â”€ Gemini AI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<FriendlyError> _askAI(String raw, StackTrace? stack) async {
    if (_model == null) return _fallback(raw);

    try {
      final stackHint = stack != null
          ? '\nStack (primeras 3 líneas):\n${stack.toString().split('\n').take(3).join('\n')}'
          : '';

      final prompt = '''
Eres un asistente de una app de MONEY MANAGER digital. Traduce errores técnicos
a lenguaje que cualquier persona entienda. La app usa pagos virtuales
y conexiones entre celulares.

Reglas:
- Responde SOLO en JSON válido, sin markdown ni backticks.
- "message": español, corto (máx 2 oraciones), amigable, con un emoji.
- "severity": "info", "warning", "error" o "critical".
- No menciones "null", "exception", "stack trace", "socket", etc.
- Sugiere una acción cuando sea posible.

Error técnico:
$raw$stackHint

Responde EXACTAMENTE así:
{"message": "...", "severity": "..."}
''';

      final response = await _model!.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';

      final json = jsonDecode(text) as Map<String, dynamic>;
      return FriendlyError(
        message: json['message'] as String? ?? _fallback(raw).message,
        severity: _parseSeverity(json['severity'] as String? ?? 'error'),
      );
    } catch (_) {
      return _fallback(raw);
    }
  }

  // â”€â”€ Fallback sin IA â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  FriendlyError _fallback(String raw) {
    final lower = raw.toLowerCase();

    if (lower.contains('bluetooth') ||
        lower.contains('ble') ||
        lower.contains('rssi') ||
        lower.contains('proximidad')) {
      return const FriendlyError(
        message:
            'Problema con la conexión BLE. Verifica que Bluetooth esté activo, mantén las aplicaciones abiertas y acerca ambos dispositivos.',
        severity: ErrorSeverity.warning,
      );
    }
    if (lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('network')) {
      return const FriendlyError(
        message:
            '\u{1F310} No se pudo conectar. Verifica que ambos dispositivos estén en la misma red.',
        severity: ErrorSeverity.warning,
      );
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return const FriendlyError(
        message: '\u{1F512} La app necesita un permiso. Revisa los ajustes.',
        severity: ErrorSeverity.error,
      );
    }
    if (lower.contains('timeout')) {
      return const FriendlyError(
        message:
            '\u{23F1}\u{FE0F} Tardó demasiado. Intenta de nuevo acercando los teléfonos.',
        severity: ErrorSeverity.warning,
      );
    }
    if (lower.contains('database') || lower.contains('sql')) {
      return const FriendlyError(
        message:
            '\u{1F4BE} Error al guardar datos. Reinicia la app si el problema persiste.',
        severity: ErrorSeverity.error,
      );
    }

    return const FriendlyError(
      message:
          '\u{26A0}\u{FE0F} Algo salió mal. Intenta de nuevo. Si persiste, reinicia la app.',
      severity: ErrorSeverity.error,
    );
  }

  ErrorSeverity _parseSeverity(String value) {
    switch (value) {
      case 'info':
        return ErrorSeverity.info;
      case 'warning':
        return ErrorSeverity.warning;
      case 'critical':
        return ErrorSeverity.critical;
      default:
        return ErrorSeverity.error;
    }
  }

  /// Limpia toda la caché de errores traducidos.
  Future<void> clearCache() async => _cache.clear();

  /// Cantidad de errores traducidos almacenados.
  Future<int> cacheSize() async => _cache.length;
}

// â”€â”€â”€ Extension: mostrar errores desde cualquier widget â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

extension FriendlyErrorDisplay on BuildContext {
  /// Traduce el error y lo muestra según severidad:
  /// - info/warning â†’ SnackBar
  /// - error/critical â†’ Dialog
  Future<void> showFriendlyError(dynamic error, [StackTrace? stack]) async {
    final friendly = await ErrorTranslatorService().translate(error, stack);
    if (!mounted) return;

    switch (friendly.severity) {
      case ErrorSeverity.info:
      case ErrorSeverity.warning:
        NotificationService().show(
          friendly.message,
          backgroundColor:
              friendly.severity == ErrorSeverity.info ? kGold : Colors.orange,
          duration: const Duration(seconds: 4),
        );
        break;
      case ErrorSeverity.error:
      case ErrorSeverity.critical:
        final color =
            friendly.severity == ErrorSeverity.critical ? kRed : Colors.orange;
        final title = friendly.severity == ErrorSeverity.critical
            ? '¡Error Crítico!'
            : 'Algo salió mal';
        showGameDialog(
          context: this,
          builder: (ctx) => AlertDialog(
            backgroundColor: kBgCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Icon(
                friendly.severity == ErrorSeverity.critical
                    ? Icons.dangerous_rounded
                    : Icons.error_outline_rounded,
                color: color,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(title,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
            ]),
            content: Text(
              friendly.message,
              style: const TextStyle(color: kTextSecondary, fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido',
                    style: TextStyle(color: kTextPrimary)),
              ),
            ],
          ),
        );
        break;
    }
  }
}

// â”€â”€â”€ Wrapper para try/catch automático â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Ejecuta [action] y si falla, traduce el error y lo muestra al usuario.
/// Retorna el resultado o null si hubo error.
Future<T?> guardedCall<T>(
  BuildContext context,
  Future<T> Function() action, {
  VoidCallback? onError,
}) async {
  try {
    return await action();
  } catch (e, stack) {
    if (context.mounted) {
      await context.showFriendlyError(e, stack);
    }
    onError?.call();
    return null;
  }
}

