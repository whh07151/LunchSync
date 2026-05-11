// ══════════════════════════════════════════════════════════
// 파일 역할: 공통 컴포넌트 라이브러리 단일 export 진입점
//
// 사용:
//   import 'package:capstone/core/components/components.dart';
//
// 디자이너 가이드 P0~P2 우선순위 위젯 6종 (신규):
//   P0  AppEmptyState        — 빈 상태
//   P0  AppStateView         — 로딩/에러/빈/정상 4 상태 분기
//   P0  AppCountdownBadge    — 카운트다운 배지 (5분 이내 강조)
//   P1  AppSectionHeader     — 섹션 제목 + 부제 + 우측 액션
//   P1  AppBadge             — 상태/카운트 배지
//   P1  AppMemberAvatar      — 멤버 프로필 원형 (호스트 별표 + 상태점)
//
// (AppPrimaryButton/AppOutlinedButton 등은 기존 core/widgets/ 에 존재 — 재사용)
// ══════════════════════════════════════════════════════════

export 'app_badge.dart';
export 'app_countdown_badge.dart';
export 'app_empty_state.dart';
export 'app_member_avatar.dart';
export 'app_section_header.dart';
export 'app_state_view.dart';
export 'app_success_overlay.dart';
