class Reaction {
  final String emoji;
  final String userId;
  final String userName;

  Reaction({required this.emoji, required this.userId, required this.userName});

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      emoji: json['emoji'] as String,
      // The user object might be nested or just an ID string
      userId: json['user'] is Map ? json['user']['_id'] : json['user'],
      userName: json['userName'] as String,
    );
  }
}
