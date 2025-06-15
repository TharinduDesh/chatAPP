// lib/models/conversation_model.dart
import 'user_model.dart';
import 'message_model.dart';

class Conversation {
  final String id;
  final List<User> participants;
  final bool isGroupChat;
  final String? groupName;
  final List<User>? groupAdmins;
  final String? groupPictureUrl;
  final Message? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  int unreadCount; // <<< Make non-final to allow client-side modification

  Conversation({
    required this.id,
    required this.participants,
    required this.isGroupChat,
    this.groupName,
    this.groupAdmins,
    this.groupPictureUrl,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
    this.unreadCount = 0, // <<< Add to constructor with default value
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    var participantsList = <User>[];
    if (json['participants'] != null) {
      json['participants'].forEach((v) {
        participantsList.add(User.fromJson(v as Map<String, dynamic>));
      });
    }

    var groupAdminsList = <User>[];
    if (json['groupAdmins'] != null && json['groupAdmins'] is List) {
      json['groupAdmins'].forEach((v) {
        groupAdminsList.add(User.fromJson(v as Map<String, dynamic>));
      });
    }

    return Conversation(
      id: json['_id'] as String,
      participants: participantsList,
      isGroupChat: json['isGroupChat'] as bool? ?? false,
      groupName: json['groupName'] as String?,
      groupAdmins: groupAdminsList.isNotEmpty ? groupAdminsList : null,
      groupPictureUrl: json['groupPictureUrl'] as String?,
      lastMessage:
          json['lastMessage'] != null
              ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
              : null,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      unreadCount: json['unreadCount'] as int? ?? 0, // <<< Parse from JSON
    );
  }

  User? getOtherParticipant(String currentUserId) {
    if (isGroupChat || participants.length < 2) return null;
    try {
      return participants.firstWhere((p) => p.id != currentUserId);
    } catch (e) {
      return null;
    }
  }
}
