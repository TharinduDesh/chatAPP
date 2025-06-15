// lib/services/user_service.dart
import 'dart:convert';
import 'dart:io'; // For File type in uploadProfilePicture
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart'; // For lookupMimeType in uploadProfilePicture
import 'package:http_parser/http_parser.dart'; // For MediaType in uploadProfilePicture

import '../config/api_constants.dart';
import '../models/user_model.dart';
import 'token_storage_service.dart';

class UserService {
  final String _usersBaseUrl = '$API_BASE_URL/users';
  final TokenStorageService _tokenStorageService = TokenStorageService();

  // Get current user's profile
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final token = await _tokenStorageService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated. No token found.',
        };
      }

      final response = await http.get(
        Uri.parse('$_usersBaseUrl/me'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': User.fromJson(responseData)};
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch profile.',
        };
      }
    } catch (e) {
      print('UserService getUserProfile Error: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  // Update user profile (fullName, email)
  Future<Map<String, dynamic>> updateUserProfile({
    required String fullName,
    required String email,
  }) async {
    try {
      final token = await _tokenStorageService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated. No token found.',
        };
      }

      final Map<String, String> body = {'fullName': fullName, 'email': email};

      final response = await http.put(
        Uri.parse('$_usersBaseUrl/me'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': User.fromJson(responseData),
          'message': responseData['message'] ?? 'Profile updated successfully!',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to update profile.',
        };
      }
    } catch (e) {
      print('UserService updateUserProfile Error: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred: ${e.toString()}',
      };
    }
  }

  // Method to upload profile picture
  Future<Map<String, dynamic>> uploadProfilePicture(File imageFile) async {
    try {
      final token = await _tokenStorageService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated. No token found.',
        };
      }

      final uri = Uri.parse('$_usersBaseUrl/me/avatar');
      var request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';

      final mimeTypeData = lookupMimeType(
        imageFile.path,
        headerBytes: [0xFF, 0xD8],
      )?.split('/');
      final image = await http.MultipartFile.fromPath(
        'avatar',
        imageFile.path,
        contentType:
            mimeTypeData != null
                ? MediaType(mimeTypeData[0], mimeTypeData[1])
                : MediaType('application', 'octet-stream'),
      );
      request.files.add(image);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': responseData,
          'message':
              responseData['message'] ??
              'Profile picture uploaded successfully!',
        };
      } else {
        print('Upload failed with status: ${response.statusCode}');
        print('Response body: ${response.body}');
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to upload profile picture.',
        };
      }
    } catch (e) {
      print('UserService uploadProfilePicture Error: $e');
      return {
        'success': false,
        'message':
            'An unexpected error occurred during upload: ${e.toString()}',
      };
    }
  }

  // New method to fetch all users
  // The backend route GET /api/users already excludes the current user.
  Future<List<User>> getAllUsers() async {
    final token = await _tokenStorageService.getToken();
    if (token == null) {
      print(
        "UserService getAllUsers: No token found, authentication required.",
      );
      throw Exception('Not authenticated: No token found.');
    }

    try {
      final response = await http.get(
        Uri.parse(_usersBaseUrl), // GET request to /api/users
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        List<User> users =
            body
                .map(
                  (dynamic item) => User.fromJson(item as Map<String, dynamic>),
                )
                .toList();
        print(
          "UserService getAllUsers: Successfully fetched ${users.length} users.",
        );
        return users;
      } else {
        print(
          'UserService getAllUsers: Failed to load users. Status: ${response.statusCode}, Body: ${response.body}',
        );
        // Attempt to parse error message from backend if available
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Failed to load users');
        } catch (_) {
          throw Exception(
            'Failed to load users (status code: ${response.statusCode})',
          );
        }
      }
    } catch (e) {
      print('UserService getAllUsers: Error fetching users: $e');
      throw Exception('Error fetching users: ${e.toString()}');
    }
  }
}
