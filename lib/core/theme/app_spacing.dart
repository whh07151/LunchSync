// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 전체에서 사용하는 여백(간격)과 모서리 둥글기를 한 곳에 모아둔 파일
//
// 왜 여기에 모으나?
//   → 디자인을 수정할 때 이 파일만 바꾸면 앱 전체에 반영됩니다.
//   → 숫자를 직접 쓰면 "16이 어디선 padding이고 어디선 margin인지"
//     헷갈리는데, 이름을 붙이면 의미가 명확해집니다.
//
// 기준: 8px 그리드 시스템
//   → 모든 여백을 4 또는 8의 배수로 맞추면 화면이 균형있게 보입니다.
//
// [모호한 부분]
//   정확한 수치는 와이어프레임 추정치. 실제 시안 확정 시 수정 필요.
// ══════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────
// AppSpacing: 여백(간격) 크기 모음
// 사용 예) SizedBox(height: AppSpacing.md)
//         Padding(padding: EdgeInsets.all(AppSpacing.lg))
// ─────────────────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  /// 4px — 가장 좁은 간격. 아이콘과 텍스트 사이 등 아주 작은 간격에 사용
  static const double xs = 4.0;

  /// 8px — 좁은 간격. 관련된 요소들 사이의 간격
  static const double sm = 8.0;

  /// 16px — 중간 간격. 가장 많이 쓰이는 기본 간격
  static const double md = 16.0;

  /// 24px — 넓은 간격. 서로 다른 섹션 사이 등에 사용
  static const double lg = 24.0;

  /// 32px — 더 넓은 간격. 화면 내 큰 구분이 필요할 때
  static const double xl = 32.0;

  /// 48px — 가장 넓은 간격. 스플래시, 온보딩 등 여유 있는 레이아웃에 사용
  static const double xxl = 48.0;

  /// 화면 좌우 안쪽 여백 — 모든 화면에서 콘텐츠가 화면 끝에 딱 붙지 않도록
  static const double screenHorizontal = 20.0;

  /// 카드 내부 여백 — 카드 안의 내용과 카드 테두리 사이 간격
  static const double cardPadding = 16.0;

  /// 섹션(구역) 사이 간격 — "추천 식당" 섹션과 "최근 주문" 섹션 사이 등
  static const double sectionGap = 24.0;

  /// 리스트 항목 사이 간격 — 식당 카드들 사이, 메뉴 항목들 사이 등
  static const double itemGap = 12.0;
}


// ─────────────────────────────────────────────────────────
// AppRadius: 모서리 둥글기(Border Radius) 모음
//
// Flutter에서 BorderRadius.circular(숫자)로 모서리를 둥글게 만듭니다.
// 숫자가 클수록 더 둥글어집니다. (0이면 직각, 매우 크면 완전한 타원)
//
// 사용 예) BorderRadius.circular(AppRadius.card)
// ─────────────────────────────────────────────────────────
class AppRadius {
  AppRadius._();

  /// 28px — 주요 버튼. 양 끝이 완전히 둥근 pill(알약) 모양이 됩니다
  static const double button = 28.0;

  /// 12px — 카드. 살짝 둥근 네모 모양
  static const double card = 12.0;

  /// 20px — 칩(태그). 버튼보다 작지만 역시 많이 둥근 모양
  static const double chip = 20.0;

  /// 10px — 입력 필드. 카드보다 조금 덜 둥근 모양
  static const double input = 10.0;

  /// 20px — 바텀시트 상단 모서리. 아래에서 올라오는 팝업의 상단만 둥글게
  static const double bottomSheet = 20.0;

  /// 6px — 작은 요소(배지, 태그 등)에 사용하는 약간의 둥글기
  static const double small = 6.0;
}
