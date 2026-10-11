/// Eine Nachricht zwischen zwei Buddys (#34, Patch 021; PilzBuddy #564).
class BuddyMessage {
  const BuddyMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    this.readAt,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? readAt;

  bool isMine(String uid) => senderId == uid;

  /// Die andere Seite des Verlaufs, von mir aus gesehen.
  String otherId(String uid) => senderId == uid ? recipientId : senderId;

  bool isUnreadFor(String uid) => recipientId == uid && readAt == null;

  factory BuddyMessage.fromJson(Map<String, dynamic> json) => BuddyMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        recipientId: json['recipient_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
      );
}
