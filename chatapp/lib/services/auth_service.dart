// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_constants.dart';
import 'token_storage_service.dart';
import '../models/user_model.dart';
import 'services_locator.dart'; // To access global userService instance for fetchAndSetCurrentUser

class AuthService {
  final String _authBaseUrl = '$API_BASE_URL/auth';
  final TokenStorageService _tokenStorageService = TokenStorageService();

  User? _currentUser;
  User? get currentUser => _currentUser;

  void setCurrentUser(User? user) {
    _currentUser = user;
    print(
      "AuthService: Current user ${user == null ? 'cleared' : 'set to ${user.fullName} (ID: ${user.id})'}.",
    );
  }

  Future<User?> fetchAndSetCurrentUser() async {
    final token = await _tokenStorageService.getToken();
    if (token != null && _currentUser == null) {
      print(
        "AuthService: Token exists, _currentUser is null. Attempting to fetch profile from server.",
      );
      try {
        // Use the global userService instance from service_locator.dart
        final profileResult = await userService.getUserProfile();
        if (profileResult['success']) {
          setCurrentUser(profileResult['data'] as User);
          print(
            "AuthService: Profile fetched and currentUser set: ${_currentUser?.fullName}",
          );
        } else {
          print(
            "AuthService: Failed to fetch profile for token. Error: ${profileResult['message']}",
          );
          // If token is invalid (e.g., 401 error from getUserProfile), log out.
          // This handles cases where a stored token might have expired or become invalid.
          String message =
              profileResult['message']?.toString().toLowerCase() ?? "";
          if (message.contains('token') ||
              message.contains('unauthorized') ||
              message.contains('not authenticated')) {
            print(
              "AuthService: Invalid token detected during profile fetch. Logging out.",
            );
            await logout(); // This will clear the token and _currentUser
          }
        }
      } catch (e) {
        print(
          "AuthService: Exception during fetchAndSetCurrentUser: $e. Logging out as a precaution.",
        );
        await logout(); // Logout if fetching profile causes an unhandled exception
      }
    } else if (_currentUser != null) {
      print(
        "AuthService: fetchAndSetCurrentUser - CurrentUser already set: ${_currentUser?.fullName}",
      );
    } else {
      print(
        "AuthService: fetchAndSetCurrentUser - No token, cannot fetch user.",
      );
    }
    return _currentUser;
  }

  Future<Map<String, dynamic>> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
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
        if (responseData['token'] != null) {
          await _tokenStorageService.storeToken(responseData['token']);
        }
        if (responseData['user'] != null) {
          setCurrentUser(User.fromJson(responseData['user']));
        }
        return {'success': true, 'data': responseData};
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Signup failed.',
        };
      }
    } catch (e) {
      print('AuthService SignUp Error: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
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
        if (responseData['token'] != null) {
          await _tokenStorageService.storeToken(responseData['token']);
        }
        if (responseData['user'] != null) {
          setCurrentUser(User.fromJson(responseData['user']));
        }
        return {'success': true, 'data': responseData};
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Login failed.',
        };
      }
    } catch (e) {
      print('AuthService Login Error: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  Future<void> logout() async {
    await _tokenStorageService.deleteToken();
    setCurrentUser(null);
    print("AuthService: User logged out, token and currentUser cleared.");
    // Note: Socket disconnection is handled by disconnectServicesOnLogout() in service_locator
  }
}
