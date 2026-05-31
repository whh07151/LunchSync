// ══════════════════════════════════════════════════════════
// 파일 역할: MenuItem 및 MenuCategory 데이터 모델 정의
//
// 연관 파일:
//   - lib/features/menu/menu_screen.dart (CU-16, 메뉴 목록/장바구니 UI)
//   - lib/providers/cart_provider.dart (장바구니 전역 상태)
//
// TODO (안태환 씨 API 연동 시):
//   - GET /restaurants/{id}/menus 응답 DTO와 필드 매핑 확인
//   - isSoldOut, options(옵션 그룹) 등 추가 필드 협의
// ══════════════════════════════════════════════════════════

/// 메뉴 카테고리 분류
///
/// 식당 메뉴를 탭으로 나눌 때 사용합니다.
/// API 연동 시 서버에서 카테고리 목록을 받아 동적으로 생성하도록 교체 예정.
///
/// 탭 추가 정책 (2026-05-14, m1 사후 정리):
///   - 기존 분류 규칙은 한식 위주의 5종(추천/밥/면/분식/음료)뿐이라
///     서버 카테고리가 "한식"/"양식"/"디저트"/"카페"/"치킨"/"피자" 등으로
///     내려오면 전부 "추천" 탭으로 쏟아져 들어가 본래 추천 메뉴와 섞였음.
///   - `other('기타')` 탭을 신설해 정확히 매칭되지 않는 메뉴는 이 탭으로
///     모으도록 _mapCategory 로직을 보강. "추천" 탭은 의도된 추천 메뉴만
///     유지되어 손님이 보는 첫 인상을 깨끗하게 유지.
enum MenuCategory {
  all('전체'),       // 전체 메뉴 보기 탭 (필터 없음)
  recommended('추천'), // 식당 추천 메뉴
  rice('밥류'),       // 밥·정식류
  noodle('면류'),     // 국수·라면류
  snack('분식'),      // 분식류
  drink('음료'),      // 음료·디저트
  other('기타');      // 분류되지 않은 카테고리 (양식/디저트/카페 등)

  const MenuCategory(this.label);

  /// 탭에 표시될 한글 레이블
  final String label;
}

/// 메뉴 항목 하나의 데이터를 담는 모델 클래스
///
/// 장바구니(cartProvider)와 메뉴 화면(CU-16)에서 공통으로 사용합니다.
class MenuItem {
  const MenuItem({
    required this.id,           // 메뉴 고유 식별자
    required this.restaurantId, // 소속 식당 ID (DB menu_items.restaurant_id)
    required this.name,         // 메뉴 이름
    required this.description,  // 메뉴 설명 (재료, 특징 등)
    required this.price,        // 가격 (원 단위 정수)
    required this.category,     // 카테고리 분류
    this.imageUrl,              // 메뉴 이미지 URL (없으면 기본 아이콘 표시)
    this.isSoldOut = false,     // 품절 여부 (기본: 판매 중)
    // CORE-09(2026-05-31): 알레르기 충돌 검증 결과를 카드에 표시하기 위한
    // 매칭 키워드 배열. 비어있으면 ⚠️ 배지를 그리지 않음.
    //
    // 백엔드 GET /api/menus/restaurant/:id/check-allergens 응답으로 채워지며,
    // 정확 매칭(소문자+trim) 결과만 들어온다.
    this.allergenConflicts = const <String>[],
    // TODO: 장다연 씨 DB 컬럼 추가 확정 후 아래 필드 활성화
    // this.spicy = false,
    // this.allergyNotes,
  });

  final String id;
  final String restaurantId; // 식당-메뉴 연결 키 (장다연 씨 기준: Menu.restaurantId = Restaurant.id)
  final String name;
  final String description;
  final int price;
  final MenuCategory category;
  final String? imageUrl;
  final bool isSoldOut;

  /// 사용자가 등록한 알레르기와 이 메뉴가 정확히 매칭된 키워드들.
  /// 비어있으면 충돌 없음 = ⚠️ 배지/BottomSheet 모두 표시 안 함.
  final List<String> allergenConflicts;
  // TODO: 장다연 씨 확정 후 추가
  // final bool spicy;
  // final String? allergyNotes;

  /// 알레르기 매칭 결과만 덮어쓰는 얕은 복사 헬퍼.
  /// 메뉴 로딩 직후 check-allergens 응답이 도착했을 때 setState 내에서 사용.
  MenuItem copyWithAllergenConflicts(List<String> conflicts) {
    return MenuItem(
      id: id,
      restaurantId: restaurantId,
      name: name,
      description: description,
      price: price,
      category: category,
      imageUrl: imageUrl,
      isSoldOut: isSoldOut,
      allergenConflicts: conflicts,
    );
  }

  // ── 가격 포맷 헬퍼 ───────────────────────────────────────
  // "6,500원" 형태로 반환. 장바구니 합계 표시에도 활용
  String get formattedPrice {
    // 세 자리마다 쉼표를 넣어 가독성 높임
    final parts = <String>[];
    var n = price;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return '${parts.join(',')}원';
  }

  // ── 동등 비교 오버라이드 ─────────────────────────────────
  // 장바구니에서 같은 메뉴가 중복 추가되지 않도록 id 기준 비교
  @override
  bool operator ==(Object other) => other is MenuItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}