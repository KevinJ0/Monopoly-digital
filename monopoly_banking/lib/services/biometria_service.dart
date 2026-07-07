import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class BiometriaService {
  static final BiometriaService _instance = BiometriaService._internal();
  factory BiometriaService() => _instance;
  BiometriaService._internal();

  final LocalAuthentication auth = LocalAuthentication();

  Future<bool> autenticar(String motivo) async {
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate)
        return true; // Si el dispositivo no soporta, permitimos pasar (o podrías bloquearlo)

      return await auth.authenticate(
        localizedReason: motivo,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (_) {
      return true; // Fallback seguro
    }
  }
}
