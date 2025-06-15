// lib/services/chat_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

import '../config/api_constants.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import 'token_storage_service.dart';

class ChatService {
  final String _conversationsBaseUrl = '$API_BASE_URL/conversations';
  final String _messagesBaseUrl = '$API_BASE_URL/messages';
  final TokenStorageService _tokenStorageService = TokenStorageService();

  Future<List<Conversation>> getConversations() async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.get(
        Uri.parse(_conversationsBaseUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body
            .map(
              (dynamic item) =>
                  Conversation.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to load conversations');
      }
    } catch (e) {
      throw Exception('Failed to load conversations: ${e.toString()}');
    }
  }

  Future<Conversation> createOrGetOneToOneConversation(
    String otherUserId,
  ) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.post(
        Uri.parse('$_conversationsBaseUrl/one-to-one'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'userId': otherUserId}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Conversation.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
          errorData['message'] ??
              'Failed to create/get one-to-one conversation',
        );
      }
    } catch (e) {
      throw Exception(
        'Failed to process one-to-one conversation: ${e.toString()}',
      );
    }
  }

  Future<List<Message>> getMessages(String conversationId) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.get(
        Uri.parse('$_messagesBaseUrl/$conversationId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body
            .map(
              (dynamic item) => Message.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to load messages');
      }
    } catch (e) {
      throw Exception('Failed to load messages: ${e.toString()}');
    }
  }

  Future<void> markAsRead(String conversationId) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) {
      print("ChatService markAsRead: No token found.");
      return;
    }

    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/$conversationId/read'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        print(
          "ChatService markAsRead: Successfully marked messages as read for convo $conversationId",
        );
      } else {
        final responseData = jsonDecode(response.body);
        print(
          'ChatService markAsRead: Failed - ${response.statusCode} ${responseData['message']}',
        );
      }
    } catch (e) {
      print('ChatService markAsRead: Exception - $e');
    }
  }

  Future<Conversation> createGroupConversation({
    required String name,
    required List<String> participantIds,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.post(
        Uri.parse('$_conversationsBaseUrl/group'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'name': name, 'participants': participantIds}),
      );
      if (response.statusCode == 201) {
        return Conversation.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to create group');
      }
    } catch (e) {
      throw Exception('Failed to create group: ${e.toString()}');
    }
  }

  Future<Conversation> uploadGroupPicture({
    required String conversationId,
    required File imageFile,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final uri = Uri.parse(
        '$_conversationsBaseUrl/group/$conversationId/picture',
      );
      var request = http.MultipartRequest('PUT', uri);
      request.headers['Authorization'] = 'Bearer $token';
      final mimeTypeData = lookupMimeType(
        imageFile.path,
        headerBytes: [0xFF, 0xD8],
      )?.split('/');
      final image = await http.MultipartFile.fromPath(
        'groupPicture',
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
        if (responseData['conversation'] != null)
          return Conversation.fromJson(
            responseData['conversation'] as Map<String, dynamic>,
          );
        else
          throw Exception(
            "Group picture uploaded, but conversation data not returned.",
          );
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to upload group picture',
        );
      }
    } catch (e) {
      throw Exception('Failed to upload group picture: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> leaveGroup(String conversationId) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/group/$conversationId/leave'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'],
          'conversation_deleted':
              responseData['conversation'] == null &&
              (responseData['message'].toLowerCase().contains('deleted') ||
                  responseData['message'].toLowerCase().contains('empty')),
          'updated_conversation':
              responseData['conversation'] != null
                  ? Conversation.fromJson(responseData['conversation'])
                  : null,
        };
      } else {
        throw Exception(responseData['message'] ?? 'Failed to leave group');
      }
    } catch (e) {
      throw Exception('Failed to leave group: ${e.toString()}');
    }
  }

  Future<Conversation> addMemberToGroup({
    required String conversationId,
    required String userIdToAdd,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/group/$conversationId/add-member'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'userId': userIdToAdd}),
      );
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['conversation'] != null) {
        return Conversation.fromJson(
          responseData['conversation'] as Map<String, dynamic>,
        );
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to add member to group',
        );
      }
    } catch (e) {
      throw Exception('Failed to add member: ${e.toString()}');
    }
  }

  Future<Conversation> removeMemberFromGroup({
    required String conversationId,
    required String userIdToRemove,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/group/$conversationId/remove-member'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'userId': userIdToRemove}),
      );
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['conversation'] != null) {
        return Conversation.fromJson(
          responseData['conversation'] as Map<String, dynamic>,
        );
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to remove member from group',
        );
      }
    } catch (e) {
      throw Exception('Failed to remove member: ${e.toString()}');
    }
  }

  Future<Conversation> updateGroupName({
    required String conversationId,
    required String newName,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');
    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/group/$conversationId/name'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'name': newName}),
      );
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['conversation'] != null) {
        return Conversation.fromJson(
          responseData['conversation'] as Map<String, dynamic>,
        );
      } else {
        throw Exception(
          responseData['message'] ?? 'Failed to update group name',
        );
      }
    } catch (e) {
      throw Exception('Failed to update group name: ${e.toString()}');
    }
  }

  Future<Conversation> promoteToAdmin({
    required String conversationId,
    required String userIdToPromote,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');

    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/group/$conversationId/promote-admin'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'userIdToPromote': userIdToPromote}),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['conversation'] != null) {
        return Conversation.fromJson(
          responseData['conversation'] as Map<String, dynamic>,
        );
      } else {
        print(
          'ChatService promoteToAdmin: Failed - ${response.statusCode} ${response.body}',
        );
        throw Exception(
          responseData['message'] ?? 'Failed to promote member to admin',
        );
      }
    } catch (e) {
      print('ChatService promoteToAdmin: Exception - $e');
      throw Exception('Failed to promote admin: ${e.toString()}');
    }
  }

  Future<Conversation> demoteAdmin({
    required String conversationId,
    required String userIdToDemote,
  }) async {
    final token = await _tokenStorageService.getToken();
    if (token == null) throw Exception('Not authenticated: No token found.');

    try {
      final response = await http.put(
        Uri.parse('$_conversationsBaseUrl/group/$conversationId/demote-admin'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({'userIdToDemote': userIdToDemote}),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['conversation'] != null) {
        return Conversation.fromJson(
          responseData['conversation'] as Map<String, dynamic>,
        );
      } else {
        print(
          'ChatService demoteAdmin: Failed - ${response.statusCode} ${response.body}',
        );
        throw Exception(responseData['message'] ?? 'Failed to demote admin');
      }
    } catch (e) {
      print('ChatService demoteAdmin: Exception - $e');
      throw Exception('Failed to demote admin: ${e.toString()}');
    }
  }
}
