// lib/models/message_model.dart
import 'user_model.dart';

class Message {
  final String id;
  final String conversationId;
  final User sender;
  final String content;
  String status; // <<< MODIFIED: Make non-final to allow client-side updates
  final DateTime createdAt;
  final DateTime updatedAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    this.status = 'sent', // <<< ADDED with default value
    required this.createdAt,
    required this.updatedAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['_id'] as String,
      conversationId: json['conversationId'] as String,
      sender: User.fromJson(json['sender']),
      content: json['content'] as String,
      status: json['status'] as String? ?? 'sent', // <<< PARSE from JSON
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
    );
  }
}
