// lib/services/biometric_service.dart
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Keys to identify the saved credentials in secure storage
  final String _emailKey = 'biometric_email';
  final String _passwordKey = 'biometric_password';

  /// Checks if the device has biometric sensors.
  Future<bool> canAuthenticate() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (e) {
      print('Error checking for biometrics: $e');
      return false;
    }
  }

  /// Prompts the user for biometric authentication.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true, // Keep the prompt open on app switch
          biometricOnly: true, // Only allow biometrics (no PIN/Pattern)
        ),
      );
    } on PlatformException catch (e) {
      print('Error during authentication: $e');
      return false;
    }
  }

  /// Saves user credentials to secure storage for future biometric logins.
  Future<void> saveCredentials(String email, String password) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  /// Retrieves the saved credentials. Returns null if none are found.
  Future<Map<String, String>?> getSavedCredentials() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);

    if (email != null && password != null) {
      return {'email': email, 'password': password};
    }
    return null;
  }

  /// Deletes saved credentials. Call this on logout or when the user disables the feature.
  Future<void> deleteCredentials() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}
