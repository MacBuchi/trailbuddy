/// Eine Freundschafts-Beziehung aus Sicht des angemeldeten Nutzers.
class FriendshipEntry {
  final String id;
  final String status; // 'pending' | 'accepted'
  final String requesterId;
  final String addresseeId;
  final String? requesterUsername;
  final String? addresseeUsername;
  final int requesterAvatar;
  final int addresseeAvatar;

  const FriendshipEntry({
    required this.id,
    required this.status,
    required this.requesterId,
    required this.addresseeId,
    this.requesterUsername,
    this.addresseeUsername,
    this.requesterAvatar = 0,
    this.addresseeAvatar = 0,
  });

  bool get isAccepted => status == 'accepted';

  bool isIncomingFor(String uid) => status == 'pending' && addresseeId == uid;

  bool isOutgoingFor(String uid) => status == 'pending' && requesterId == uid;

  String otherUsername(String uid) =>
      (requesterId == uid ? addresseeUsername : requesterUsername) ?? 'Buddy';

  int otherAvatar(String uid) =>
      requesterId == uid ? addresseeAvatar : requesterAvatar;

  /// Die id des jeweils anderen.
  String otherId(String uid) => requesterId == uid ? addresseeId : requesterId;

  factory FriendshipEntry.fromJson(
    Map<String, dynamic> json,
  ) => FriendshipEntry(
    id: json['id'] as String,
    status: json['status'] as String,
    requesterId: json['requester_id'] as String,
    addresseeId: json['addressee_id'] as String,
    requesterUsername:
        (json['requester'] as Map<String, dynamic>?)?['username'] as String?,
    addresseeUsername:
        (json['addressee'] as Map<String, dynamic>?)?['username'] as String?,
    requesterAvatar:
        (json['requester'] as Map<String, dynamic>?)?['avatar'] as int? ?? 0,
    addresseeAvatar:
        (json['addressee'] as Map<String, dynamic>?)?['avatar'] as int? ?? 0,
  );
}

/// Suchtreffer der Buddy-Suche.
class ProfileSearchResult {
  final String id;
  final String username;
  final String? displayName;
  final int avatar;

  const ProfileSearchResult({
    required this.id,
    required this.username,
    this.displayName,
    this.avatar = 0,
  });

  factory ProfileSearchResult.fromJson(Map<String, dynamic> json) =>
      ProfileSearchResult(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatar: json['avatar'] as int? ?? 0,
      );
}

/// Jemand, den ICH blockiert habe (#584, `my_blocks()`).
class BlockedUser {
  final String id;
  final String username;
  final int avatar;
  final DateTime createdAt;

  const BlockedUser({
    required this.id,
    required this.username,
    this.avatar = 0,
    required this.createdAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    id: json['blocked_id'] as String,
    username: json['username'] as String? ?? 'Buddy',
    avatar: json['avatar'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// Warum gemeldet wird — dieselben Werte wie der Check an
/// `content_reports.reason` (Patch 033).
enum ReportReason {
  spam('spam'),
  abuse('abuse'),
  inappropriate('inappropriate'),
  other('other');

  const ReportReason(this.wire);

  final String wire;
}
