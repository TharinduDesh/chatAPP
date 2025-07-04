// lib/models/message_model.dart
import 'user_model.dart';
import 'reaction_model.dart';

class Message {
  final String id;
  final String conversationId;
  final User? sender;
  final String content;
  String status;
  final String? messageType;
  final List<Reaction> reactions;
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isEdited;
  final DateTime? deletedAt;
  final String? replyTo;
  final String? replySnippet;
  final String? replySenderName;

  Message({
    required this.id,
    required this.conversationId,
    this.sender,
    required this.content,
    this.messageType,
    this.reactions = const [],
    this.status = 'sent',
    this.fileUrl,
    this.fileType,
    this.fileName,
    required this.createdAt,
    required this.updatedAt,
    this.isEdited = false,
    this.deletedAt,
    this.replyTo,
    this.replySnippet,
    this.replySenderName,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['_id'] as String,
      conversationId: json['conversationId'] as String,
      sender:
          json['sender'] != null
              ? User.fromJson(json['sender'] as Map<String, dynamic>)
              : null,
      content: json['content'] as String,
      reactions:
          (json['reactions'] as List<dynamic>?)
              ?.map((e) => Reaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      messageType: json['messageType'] as String? ?? 'text',
      status: json['status'] as String? ?? 'sent',
      fileUrl: json['fileUrl'] as String?,
      fileType: json['fileType'] as String?,
      fileName: json['fileName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      isEdited: json['isEdited'] as bool? ?? false,
      deletedAt:
          json['deletedAt'] != null
              ? DateTime.parse(json['deletedAt'] as String).toLocal()
              : null,
      replyTo: json['replyTo'] as String?,
      replySnippet: json['replySnippet'] as String?,
      replySenderName: json['replySenderName'] as String?,
    );
  }
}
