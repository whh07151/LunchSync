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
enum MenuCategory {
  all('전체'),       // 전체 메뉴 보기 탭 (필터 없음)
  recommended('추천'), // 식당 추천 메뉴
  rice('밥류'),       // 밥·정식류
  noodle('면류'),     // 국수·라면류
  snack('분식'),      // 분식류
  drink('음료');      // 음료·디저트

  const MenuCategory(this.label);

  /// 탭에 표시될 한글 레이블
  final String label;
}

/// 메뉴 항목 하나의 데이터를 담는 모델 클래스
///
/// 장바구니(cartProvider)와 메뉴 화면(CU-16)에서 공통으로 사용합니다.
class MenuItem {
  const MenuItem({
    required this.id,          // 메뉴 고유 식별자
    required this.name,        // 메뉴 이름
    required this.description, // 메뉴 설명 (재료, 특징 등)
    required this.price,       // 가격 (원 단위 정수)
    required this.category,    // 카테고리 분류
    this.imageUrl,             // 메뉴 이미지 URL (없으면 기본 아이콘 표시)
    this.isSoldOut = false,    // 품절 여부 (기본: 판매 중)
  });

  final String id;
  final String name;
  final String description;
  final int price;
  final MenuCategory category;
  final String? imageUrl;
  final bool isSoldOut;

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