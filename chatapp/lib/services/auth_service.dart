// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_constants.dart';
import 'token_storage_service.dart';
import '../models/user_model.dart';
import 'services_locator.dart';
import 'crypto_service.dart';

class AuthService {
  final String _authBaseUrl = '$API_BASE_URL/auth';
  final TokenStorageService _tokenStorageService = TokenStorageService();
  final CryptoService _cryptoService = CryptoService();

  User? _currentUser;
  User? get currentUser => _currentUser;

  void setCurrentUser(User? user) {
    _currentUser = user;
    print("AuthService: Current user set to ${user?.fullName}");
  }

  // ✅ DEFINITIVE FIX: This method now ensures keys are fully loaded/generated.
  Future<void> _handleLoginSuccess() async {
    try {
      // ✅ DEFINITIVE FIX: Start the crypto initialization, but don't wait here.
      // Other services will wait on the `cryptoService.ready` future.
      _cryptoService.init();

      // Upload the public key to the server.
      await _cryptoService
          .ready; // Ensure keys are generated before getting public key
      final myPublicKey = await _cryptoService.getMyPublicKey();

      final token = await _tokenStorageService.getToken();
      await http.post(
        Uri.parse('$API_BASE_URL/keys/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'publicKey': myPublicKey}),
      );
      print("✅ AuthService: Public key upload initiated.");
    } catch (e) {
      print("❌ AuthService: Key setup error: $e");
    }
  }

  Future<User?> fetchAndSetCurrentUser() async {
    final token = await _tokenStorageService.getToken();
    if (token != null && _currentUser == null) {
      try {
        final profileResult = await userService.getUserProfile();
        if (profileResult['success']) {
          setCurrentUser(profileResult['data'] as User);
          // After fetching the user, wait for their keys to be ready.
          await _handleLoginSuccess();
        } else {
          await logout();
        }
      } catch (e) {
        await logout();
      }
    }
    return _currentUser;
  }

  Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      // ... (http.post for signup remains the same)
      final response = await http.post(
        Uri.parse('$_authBaseUrl/signup'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'fullName': fullName,
          'email': email,
          'password': password,
        }),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 201) {
        if (responseData['token'] != null)
          await _tokenStorageService.storeToken(responseData['token']);
        if (responseData['user'] != null)
          setCurrentUser(User.fromJson(responseData['user']));

        // This will generate and upload keys for the new user
        await _handleLoginSuccess();

        return {'success': true, 'data': responseData};
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Signup failed.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      // ... (http.post for login remains the same)
      final response = await http.post(
        Uri.parse('$_authBaseUrl/login'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'email': email,
          'password': password,
        }),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (responseData['token'] != null)
          await _tokenStorageService.storeToken(responseData['token']);
        if (responseData['user'] != null)
          setCurrentUser(User.fromJson(responseData['user']));

        // ✅ After a successful login, ensure the user's keys are ready.
        await _handleLoginSuccess();

        return {'success': true, 'data': responseData};
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Login failed.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'An unexpected error: ${e.toString()}',
      };
    }
  }

  Future<void> logout() async {
    await _tokenStorageService.deleteToken();
    setCurrentUser(null);
  }
}
