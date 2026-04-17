// ══════════════════════════════════════════════════════════
// 파일 역할: 메뉴 화면(CU-16) 표시 기준 및 우선순위
//
// 용도:
//   - 메뉴 목록에서 항목별 표시 우선순위 결정
//   - 알레르기/맵기/대표메뉴 배지 표시 기준
//   - 품절 표시 규칙
//
// 연관 파일:
//   - lib/features/menu/menu_screen.dart (메뉴 목록 UI)
//   - lib/models/menu_item.dart (MenuItem 모델)
//   - lib/data/seeds/menu_seeds.dart (메뉴 시드 데이터)
// ══════════════════════════════════════════════════════════

/// 메뉴 항목 표시 우선순위 설정
class MenuDisplayConfig {
  MenuDisplayConfig._();

  /// 메뉴 카드에 표시할 필드 우선순위 (위에서부터 중요)
  ///
  /// 화면 공간이 부족할 때 아래쪽 필드부터 생략
  static const List<String> fieldPriority = [
    'name',         // 1순위: 메뉴명 (항상 표시)
    'price',        // 2순위: 가격 (항상 표시)
    'description',  // 3순위: 설명 (1줄까지)
    'spiceLevel',   // 4순위: 맵기 배지 (있을 때만)
    'allergens',    // 5순위: 알레르기 배지 (있을 때만)
    'imageUrl',     // 6순위: 이미지 (있을 때만)
  ];

  /// 메뉴 설명 최대 표시 길이 (초과 시 말줄임)
  static const int maxDescriptionLength = 40;

  /// 맵기 표시 기준
  ///
  /// spiceLevel 값에 따른 표시 텍스트와 아이콘 색상
  static const Map<int, MenuSpiceBadge> spiceBadges = {
    0: MenuSpiceBadge(label: '순한맛', icon: '🌿'),
    1: MenuSpiceBadge(label: '약간 매움', icon: '🌶️'),
    2: MenuSpiceBadge(label: '매움', icon: '🌶️🌶️'),
    3: MenuSpiceBadge(label: '아주 매움', icon: '🌶️🌶️🌶️'),
  };

  /// 알레르기 배지 표시 기준
  ///
  /// 주요 알레르겐만 배지로 표시 (한국 식약처 기준 주요 8종)
  static const List<String> majorAllergens = [
    'dairy',      // 우유
    'egg',        // 계란
    'wheat',      // 밀
    'soy',        // 대두
    'peanut',     // 땅콩
    'treenut',    // 견과류
    'shellfish',  // 갑각류
    'fish',       // 생선
  ];

  /// 알레르겐 코드 → 배지 표시 라벨
  static const Map<String, String> allergenBadgeLabels = {
    'dairy': '유제품',
    'egg': '계란',
    'wheat': '밀',
    'soy': '대두',
    'peanut': '땅콩',
    'treenut': '견과류',
    'shellfish': '갑각류',
    'fish': '생선',
    'pork': '돼지고기',
    'beef': '소고기',
  };

  /// 품절 메뉴 표시 규칙
  static const String soldOutLabel = '품절';
  static const double soldOutOpacity = 0.5;

  /// 대표 메뉴 배지 라벨
  static const String signatureLabel = '대표';

  /// 카테고리별 정렬 순서 (메뉴 탭 순서)
  ///
  /// menu_item.dart의 MenuCategory enum 순서와 일치
  static const List<String> categoryOrder = [
    '전체',
    '추천',
    '밥류',
    '면류',
    '분식',
    '양식',
    '음료',
    '디저트',
  ];
}

/// 맵기 배지 데이터
class MenuSpiceBadge {
  const MenuSpiceBadge({required this.label, required this.icon});

  final String label;
  final String icon;
}
