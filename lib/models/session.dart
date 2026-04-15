// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 데이터 모델
//
// 세션 상태 흐름:
//   WAITING → VOTING → ORDERED → DONE
//
// 백엔드 응답 DTO와 1:1 매핑.
// createdBy는 { id, name } 객체로 내려옴 (UUID 문자열 아님).
//
// CU-09 추가 필드 (세션 생성 시 설정):
//   radius        — 식당 검색 반경 (미터)
//   budget        — 1인당 예산 상한 (원)
//   returnMinutes — 복귀 여유 시간 (분)
//   memo          — 자유 메모
// ══════════════════════════════════════════════════════════

/// 세션 생성자 정보 (백엔드 createdBy 필드와 매핑)
class SessionCreator {
  const SessionCreator({
    required this.id,
    required this.name,
  });

  final String id;
  final String? name; // 유저 이름 (조회 실패 시 null 가능)

  factory SessionCreator.fromJson(Map<String, dynamic> json) {
    return SessionCreator(
      id: json['id'] as String,
      name: json['name'] as String?,
    );
  }
}

class Session {
  const Session({
    required this.id,
    required this.name,
    required this.status,
    this.statusLabel,
    this.createdBy,
    this.memberCount,
    this.winnerRestaurantId,
    this.scheduledAt,
    this.radius,
    this.budget,
    this.returnMinutes,
    this.memo,
    this.createdAt,
  });

  final String id;
  final String name;
  final String status; // WAITING | VOTING | ORDERED | DONE
  final String? statusLabel;    // 한글 레이블 (백엔드 제공, 목록 화면용)
  final SessionCreator? createdBy; // 생성자 정보 객체
  final int? memberCount;       // 참여 인원 수 (목록 응답에서만 제공)
  final String? winnerRestaurantId;
  final String? scheduledAt;
  final int? radius;            // 식당 검색 반경 (미터)
  final int? budget;            // 1인당 예산 상한 (원)
  final int? returnMinutes;     // 복귀 여유 시간 (분)
  final String? memo;           // 자유 메모
  final String? createdAt;

  factory Session.fromJson(Map<String, dynamic> json) {
    // createdBy: 백엔드가 { id, name } 객체로 내려줌
    final createdByJson = json['createdBy'];
    final creator = createdByJson is Map<String, dynamic>
        ? SessionCreator.fromJson(createdByJson)
        : null;

    return Session(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      statusLabel: json['statusLabel'] as String?,
      createdBy: creator,
      memberCount: json['memberCount'] as int?,
      winnerRestaurantId: json['winnerRestaurantId'] as String?,
      scheduledAt: json['scheduledAt'] as String?,
      radius: json['radius'] as int?,
      budget: json['budget'] as int?,
      returnMinutes: json['returnMinutes'] as int?,
      memo: json['memo'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

/// 세션 멤버 정보 (GET /sessions/:id/members 응답의 members[] 항목)
class SessionMember {
  const SessionMember({
    required this.id,
    this.name,
    this.profileImage,
    this.org,
    this.isHost = false,
    this.joinedAt,
  });

  final String id; // user_id (백엔드가 'id' 키로 반환)
  final String? name;
  final String? profileImage;
  final String? org;
  final bool isHost; // 세션 생성자 여부
  final String? joinedAt;

  factory SessionMember.fromJson(Map<String, dynamic> json) {
    return SessionMember(
      id: json['id'] as String, // 백엔드 getSessionMembers는 'id' 키로 반환
      name: json['name'] as String?,
      profileImage: json['profileImage'] as String?,
      org: json['org'] as String?,
      isHost: json['isHost'] as bool? ?? false,
      joinedAt: json['joinedAt'] as String?,
    );
  }
}

/// GET /sessions/:id/members 전체 응답 래퍼
/// 백엔드: { totalCount, joinedCount, members[] }
class SessionMembersResponse {
  const SessionMembersResponse({
    required this.totalCount,
    required this.joinedCount,
    required this.members,
  });

  final int totalCount;
  final int joinedCount;
  final List<SessionMember> members;

  factory SessionMembersResponse.fromJson(Map<String, dynamic> json) {
    final list = json['members'] as List<dynamic>? ?? [];
    return SessionMembersResponse(
      totalCount: json['totalCount'] as int? ?? 0,
      joinedCount: json['joinedCount'] as int? ?? 0,
      members: list
          .map((e) => SessionMember.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
