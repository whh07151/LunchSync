// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 데이터 모델
//
// 세션 상태 흐름:
//   WAITING → VOTING → DECIDED → COMPLETED
// ══════════════════════════════════════════════════════════

class Session {
  const Session({
    required this.id,
    required this.name,
    required this.status,
    required this.createdBy,
    this.winnerRestaurantId,
    this.scheduledAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String status; // WAITING | VOTING | DECIDED | COMPLETED
  final String createdBy; // 생성자 userId
  final String? winnerRestaurantId;
  final String? scheduledAt;
  final String? createdAt;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      createdBy: json['createdBy'] as String,
      winnerRestaurantId: json['winnerRestaurantId'] as String?,
      scheduledAt: json['scheduledAt'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

/// 세션 멤버 정보
class SessionMember {
  const SessionMember({
    required this.userId,
    this.name,
    this.profileImage,
    this.org,
    this.joinedAt,
  });

  final String userId;
  final String? name;
  final String? profileImage;
  final String? org;
  final String? joinedAt;

  factory SessionMember.fromJson(Map<String, dynamic> json) {
    return SessionMember(
      userId: json['userId'] as String,
      name: json['name'] as String?,
      profileImage: json['profileImage'] as String?,
      org: json['org'] as String?,
      joinedAt: json['joinedAt'] as String?,
    );
  }
}
