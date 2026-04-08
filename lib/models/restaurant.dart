// ══════════════════════════════════════════════════════════
// 파일 역할: Restaurant 데이터 모델 정의
//
// 연관 파일:
//   - lib/models/tag.dart (태그 체계)
//   - lib/models/menu_item.dart (식당별 메뉴)
//   - lib/data/seeds/restaurant_seeds.dart (시드 데이터)
//
// TODO (API 연동 시):
//   - GET /restaurants 응답 DTO와 필드 매핑 확인
//   - 운영시간, 휴무일, 좌석수 등 추가 필드 협의
// ══════════════════════════════════════════════════════════

import 'tag.dart';

/// 식당 카테고리 분류
///
/// 식당 목록을 필터링할 때 사용합니다.
enum RestaurantCategory {
  all('전체'),
  korean('한식'),
  chinese('중식'),
  japanese('일식'),
  western('양식'),
  snack('분식'),
  cafe('카페'),
  etc('기타');

  const RestaurantCategory(this.label);

  /// 탭/필터에 표시될 한글 레이블
  final String label;
}

/// 식당 하나의 데이터를 담는 모델 클래스
///
/// 식당 목록, 상세, 비교 화면에서 공통으로 사용합니다.
class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.tags,
    this.imageUrl,
    this.address,
    this.phone,
    this.priceRange,
    this.rating,
    this.walkingMinutes,
    this.isClosed = false,
  });

  final String id;           // 식당 고유 식별자
  final String name;         // 식당 이름
  final RestaurantCategory category; // 카테고리 분류
  final String description;  // 식당 설명문 (특징, 분위기 등)
  final List<Tag> tags;      // 태그 목록 (맵기, 가격대, 분위기 등)
  final String? imageUrl;    // 대표 이미지 URL
  final String? address;     // 주소
  final String? phone;       // 전화번호
  final String? priceRange;  // 가격대 표시 (예: "6,000~9,000원")
  final double? rating;      // 평점 (0.0 ~ 5.0)
  final int? walkingMinutes; // 도보 소요 시간 (분)
  final bool isClosed;       // 영업 종료 여부 (기본: 영업 중)

  // ── 가격대 요약 헬퍼 ────────────────────────────────────
  String get priceDisplay => priceRange ?? '가격 정보 없음';

  // ── 도보 시간 헬퍼 ──────────────────────────────────────
  String get walkingDisplay =>
      walkingMinutes != null ? '도보 $walkingMinutes분' : '거리 정보 없음';

  // ── 동등 비교 오버라이드 ─────────────────────────────────
  @override
  bool operator ==(Object other) =>
      other is Restaurant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
