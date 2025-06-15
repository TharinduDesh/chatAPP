// lib/services/token_storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorageService {
  final _storage = const FlutterSecureStorage();
  static const String _tokenKey = 'authToken'; // Key for storing the token

  // Store the token
  Future<void> storeToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      print('Token stored successfully');
    } catch (e) {
      print('Error storing token: $e');
    }
  }

  // Retrieve the token
  Future<String?> getToken() async {
    try {
      final String? token = await _storage.read(key: _tokenKey);
      print('Token retrieved: ${token != null ? "Exists" : "Not found"}');
      return token;
    } catch (e) {
      print('Error retrieving token: $e');
      return null;
    }
  }

  // Delete the token (for logout)
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
      print('Token deleted successfully');
    } catch (e) {
      print('Error deleting token: $e');
    }
  }
}
