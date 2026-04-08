// ══════════════════════════════════════════════════════════
// 파일 역할: Tag 데이터 모델 및 태그 그룹 정의
//
// 연관 파일:
//   - lib/models/restaurant.dart (식당에 태그 부착)
//   - lib/models/menu_item.dart (메뉴에 태그 부착 가능)
//
// TODO (API 연동 시):
//   - GET /tags 응답과 필드 매핑 확인
//   - 사용자 커스텀 태그 지원 여부 협의
// ══════════════════════════════════════════════════════════

/// 태그가 속하는 그룹 분류
///
/// 태그를 그룹별로 묶어 필터 UI를 구성할 때 사용합니다.
enum TagGroup {
  taste('맛'),         // 맵기, 달기, 짠맛 등
  price('가격대'),     // 저렴, 보통, 고급
  mood('분위기'),      // 조용한, 활기찬, 혼밥 등
  dietary('식이제한'), // 채식, 할랄, 글루텐프리 등
  feature('특징');     // 빠른식사, 단체가능, 포장가능 등

  const TagGroup(this.label);

  /// 필터 UI에 표시될 한글 레이블
  final String label;
}

/// 태그 하나의 데이터를 담는 모델 클래스
///
/// 식당/메뉴에 부착하여 필터링·추천·제외 로직에 활용합니다.
class Tag {
  const Tag({
    required this.id,
    required this.label,
    required this.group,
    this.emoji,
  });

  final String id;        // 태그 고유 식별자 (예: "spicy_high")
  final String label;     // 표시 텍스트 (예: "매운맛")
  final TagGroup group;   // 소속 그룹
  final String? emoji;    // 태그 앞에 표시할 이모지 (선택)

  // ── 동등 비교 오버라이드 ─────────────────────────────────
  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => emoji != null ? '$emoji $label' : label;
}
