// lib/models/user_model.dart
class User {
  final String id;
  final String fullName;
  final String email;
  final String? profilePictureUrl; // Nullable as it might not always be there
  final DateTime? createdAt;
  final DateTime? lastSeen;

  User({
    required this.id,
    required this.fullName,
    required this.email,
    this.profilePictureUrl,
    this.createdAt,
    this.lastSeen,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] as String,
      fullName: json['fullName'] as String,
      email: json['email'] as String,
      profilePictureUrl: json['profilePictureUrl'] as String?,
      createdAt:
          json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'] as String)
              : null,
      lastSeen:
          json['lastSeen'] != null
              ? DateTime.tryParse(json['lastSeen'] as String)?.toLocal()
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'fullName': fullName,
      'email': email,
      'profilePictureUrl': profilePictureUrl,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
