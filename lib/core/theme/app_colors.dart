import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: LunchSync 앱 전체에서 사용하는 색상을 한 곳에 모아둔 파일
//
// 왜 색상을 여기에 모으나?
//   → 나중에 색상을 바꾸고 싶을 때 이 파일만 수정하면
//     앱 전체에 자동으로 반영되기 때문입니다.
//     (파일마다 직접 색상을 적으면 수백 곳을 수정해야 함)
//
// [모호한 부분]
//   정확한 HEX 색상 코드는 PDF 와이어프레임 기반 추정치입니다.
//   실제 디자인 시안이 확정되면 이 파일의 숫자만 바꾸면 됩니다.
// ══════════════════════════════════════════════════════════


// ─────────────────────────────────────────────────────────
// 손님앱 (Customer App) 전용 색상 — 따뜻한 주황 계열
//
// 손님이 사용하는 앱은 친근하고 따뜻한 느낌을 주기 위해 주황색을 사용합니다.
// ─────────────────────────────────────────────────────────
class CustomerColors {
  // 외부에서 CustomerColors() 처럼 직접 만들지 못하게 막는 코드
  // (색상은 인스턴스를 만들 필요 없이 CustomerColors.primary 처럼 바로 씁니다)
  CustomerColors._();

  /// 주요 강조색 — 버튼, 활성 탭, 주요 아이콘 등에 사용
  static const Color primary = Color(0xFFFF8C42);

  /// 주요 강조색의 진한 버전 — 버튼을 눌렀을 때(pressed) 상태 등에 사용
  static const Color primaryDark = Color(0xFFE67A30);

  /// 주요 강조색의 연한 버전 — 그라디언트, 보조 장식 등에 사용
  static const Color primaryLight = Color(0xFFFFAD72);

  /// 주요 강조색의 매우 옅은 배경색 — 카드 배경, 선택된 항목 배경 등에 사용
  static const Color primarySurface = Color(0xFFFFF5F0);

  /// 보조 강조색 — primary와 함께 사용하는 두 번째 색상
  static const Color secondary = Color(0xFFFF6B35);
}


// ─────────────────────────────────────────────────────────
// 점주앱 (Owner App) 전용 색상 — 청록/민트 계열
//
// 점주가 사용하는 앱은 전문적이고 신뢰감 있는 느낌을 주기 위해
// 손님앱과 다른 색상(청록)을 사용합니다.
// 같은 Flutter 앱이지만 색상만 바뀌어 두 앱이 구분됩니다.
// ─────────────────────────────────────────────────────────
class OwnerColors {
  OwnerColors._();

  /// 주요 강조색 — 청록/민트 계열
  static const Color primary = Color(0xFF1DBFA3);

  /// 주요 강조색의 진한 버전
  static const Color primaryDark = Color(0xFF189E88);

  /// 주요 강조색의 연한 버전
  static const Color primaryLight = Color(0xFF4ECFBB);

  /// 주요 강조색의 매우 옅은 배경색
  static const Color primarySurface = Color(0xFFF0FBF9);
}


// ─────────────────────────────────────────────────────────
// 공통 색상 — 손님앱과 점주앱 모두에서 사용하는 색상
// ─────────────────────────────────────────────────────────
class AppColors {
  AppColors._();

  // ── 배경색 ──────────────────────────────────────────────
  /// 화면 전체 배경 — 순수 흰색
  static const Color background = Color(0xFFFFFFFF);

  /// 약간 회색이 도는 배경 — 리스트 항목 구분 등에 사용
  static const Color backgroundGrey = Color(0xFFFAFAFA);

  /// 카드, 팝업 등 위에 올라오는 요소의 배경색
  static const Color surface = Color(0xFFFFFFFF);

  // ── 텍스트 색상 ─────────────────────────────────────────
  /// 가장 중요한 텍스트 — 제목, 본문 등 (거의 검정)
  static const Color textPrimary = Color(0xFF1A1A1A);

  /// 보조 텍스트 — 부제목, 설명 등 (중간 회색)
  static const Color textSecondary = Color(0xFF666666);

  /// 힌트 텍스트 — 입력 필드의 안내 문구 등 (밝은 회색)
  static const Color textHint = Color(0xFF999999);

  /// 비활성화된 텍스트 — 선택할 수 없는 항목 등 (더 밝은 회색)
  static const Color textDisabled = Color(0xFFCCCCCC);

  // ── 구분선 / 테두리 ─────────────────────────────────────
  /// 항목 사이 구분선 색상 — 매우 연한 회색
  static const Color divider = Color(0xFFEEEEEE);

  /// 입력창, 카드 등의 테두리 색상
  static const Color border = Color(0xFFDDDDDD);

  /// 입력창이 선택(포커스)되었을 때 테두리 색상
  static const Color borderFocus = Color(0xFF1A1A1A);

  // ── 상태 색상 (앱 전체 공통) ────────────────────────────
  /// 성공 / 완료 상태를 나타내는 초록색
  static const Color success = Color(0xFF27AE60);

  /// 오류 / 실패 상태를 나타내는 빨간색
  static const Color error = Color(0xFFE74C3C);

  /// 경고 상태를 나타내는 노란색/주황색
  static const Color warning = Color(0xFFF39C12);

  /// 정보 안내를 나타내는 파란색
  static const Color info = Color(0xFF3498DB);

  // ── 비활성화 상태 ───────────────────────────────────────
  /// 비활성화된 버튼, 아이콘 등의 색상
  static const Color disabled = Color(0xFFCCCCCC);

  /// 비활성화된 요소의 배경색
  static const Color disabledBackground = Color(0xFFF5F5F5);

  // ── 아이콘 색상 ─────────────────────────────────────────
  /// 현재 선택된(활성) 아이콘 색상
  static const Color iconActive = Color(0xFF1A1A1A);

  /// 선택되지 않은(비활성) 아이콘 색상
  static const Color iconInactive = Color(0xFFCCCCCC);

  // ── 오버레이 ────────────────────────────────────────────
  /// 바텀시트, 다이얼로그 뒤에 깔리는 반투명 검정 배경
  /// 0x80 = 알파값 128 = 약 50% 투명도
  static const Color overlay = Color(0x80000000);
}
