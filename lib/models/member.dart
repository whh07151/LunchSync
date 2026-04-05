// ══════════════════════════════════════════════════════════
// 파일 역할: Member 데이터 모델 정의
//
// 왜 별도 파일로 분리했나?
//   Member는 CU-08(멤버 선택)에서 선택되고,
//   sessionProvider(전역 상태)에 저장되며,
//   CU-09(세션 생성, 우현호 담당)에서 읽혀야 합니다.
//   여러 파일이 같은 타입을 써야 하므로 별도 모델 파일로 분리합니다.
//
// 연관 파일:
//   - lib/features/session/member_select_screen.dart (CU-08, 선택 UI)
//   - lib/providers/session_provider.dart (전역 상태 저장)
//   - lib/features/session/session_create_screen.dart (CU-09, 우현호 담당 — 미구현)
// ══════════════════════════════════════════════════════════

/// 멤버(함께 점심을 먹을 사람) 한 명의 데이터를 담는 모델 클래스
///
/// 현재 필드는 UI 표시용 최소 구성입니다.
/// CU-09(세션 생성, 우현호 담당)와 연동 시 필드 추가가 필요할 수 있습니다.
///
/// TODO (우현호 씨와 CU-09 연동 시 협의):
///   - kakaoId: 카카오 친구 API에서 받아오는 식별자
///   - profileImageUrl: 카카오 프로필 이미지 URL
///   위 필드가 추가되더라도 이 클래스에만 추가하면 되므로 영향 범위 최소화
class Member {
  const Member({
    required this.id,           // 사용자 고유 식별자 (서버 ID 또는 카카오 ID)
    required this.name,         // 사용자 이름 (표시용)
    required this.organization, // 소속 (팀명, 부서명 등 — UI 표시용)
  });

  final String id;
  final String name;
  final String organization;

  // ── 동등 비교 오버라이드 ─────────────────────────────────
  // Provider 상태 비교, Set 중복 제거 등에서 id 기준으로 동등성 판단이 필요함
  @override
  bool operator ==(Object other) => other is Member && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Member(id: $id, name: $name, org: $organization)';
}