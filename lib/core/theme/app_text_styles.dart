import 'package:flutter/material.dart';
import 'app_colors.dart';

// 앱 기본 글꼴 패밀리 — pubspec 에 번들된 Noto Sans KR(한글 포함).
// google_fonts 런타임 페치 대신 로컬 에셋을 써서 첫 프레임부터 한글
// 글리프가 존재하게 함 (웹 폰트 폴백 경고 제거).
const String kAppFontFamily = 'NotoSansKR';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 전체에서 사용하는 글자 스타일(폰트)을 한 곳에 모아둔 파일
//
// 왜 여기에 모으나?
//   → 폰트 크기나 굵기를 바꾸고 싶을 때 이 파일만 수정하면
//     앱 전체에 자동으로 반영되기 때문입니다.
//
// [모호한 부분]
//   - PDF에 폰트 이름이 명시되어 있지 않음
//   → 한글을 잘 지원하고 PDF 분위기와 가장 유사한 'Noto Sans' 사용
//   - 정확한 px(픽셀) 수치가 없음 → 업계 표준 수치로 추정
// ══════════════════════════════════════════════════════════

class AppTextStyles {
  AppTextStyles._();

  // ── 기본 스타일 ─────────────────────────────────────────
  // 모든 글자 스타일의 베이스가 되는 기본값
  // 다른 스타일들은 이걸 복사(copyWith)해서 일부만 바꿉니다
  // 번들된 NotoSansKR(한글 포함) 사용 — docs "한글 최적화" 의도와 일치.
  static const TextStyle _base = TextStyle(
    fontFamily: kAppFontFamily,
    color: AppColors.textPrimary, // 기본 글자색: 거의 검정
    letterSpacing: -0.3,         // 글자 간격을 살짝 좁힘 (한글에 더 자연스러움)
  );


  // ── 제목 스타일 (Heading) ───────────────────────────────
  // 화면의 가장 큰 제목 — 예: "오늘 점심 어디가?" 같은 메인 타이틀
  static TextStyle get heading1 => _base.copyWith(
        fontSize: 28,             // 글자 크기 28px
        fontWeight: FontWeight.w700, // 굵기: Bold (숫자가 클수록 굵음, 100~900)
        height: 1.3,              // 줄 간격: 글자 크기의 1.3배
      );

  // 두 번째 크기 제목 — 예: 섹션 제목, 팝업 제목
  static TextStyle get heading2 => _base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.35,
      );

  // 세 번째 크기 제목 — 예: 앱바 제목, 카드 제목
  static TextStyle get heading3 => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600, // SemiBold: Bold보다 살짝 얇음
        height: 1.4,
      );


  // ── 본문 스타일 (Body) ──────────────────────────────────
  // 큰 본문 — 예: 설명 텍스트, 리스트 항목의 주요 내용
  static TextStyle get bodyLarge => _base.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400, // Regular: 일반 굵기
        height: 1.6,                 // 줄 간격을 넓게 → 읽기 편함
      );

  // 중간 본문 — 예: 일반적인 텍스트, 입력창 내용
  static TextStyle get bodyMedium => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
      );

  // 작은 본문 — 예: 부가 설명, 날짜, 거리 정보 등
  static TextStyle get bodySmall => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: AppColors.textSecondary, // 기본보다 연한 회색으로 강조도를 낮춤
      );


  // ── 버튼 텍스트 스타일 ──────────────────────────────────
  // 큰 버튼 안의 텍스트 — 예: "시작하기", "다음" 버튼
  static TextStyle get buttonLarge => _base.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.0,    // 버튼은 줄 간격이 필요 없으므로 1.0
        letterSpacing: 0,
      );

  // 중간 버튼 안의 텍스트 — 예: 소형 버튼, 텍스트 링크
  static TextStyle get buttonMedium => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.0,
        letterSpacing: 0,
      );


  // ── 캡션 스타일 (Caption) ───────────────────────────────
  // 가장 작은 텍스트 — 예: 이미지 아래 설명, 타임스탬프, 법적 고지 등
  static TextStyle get caption => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: AppColors.textHint, // 가장 연한 회색 → 주목도가 낮은 정보
      );


  // ── 라벨 스타일 (Label) ─────────────────────────────────
  // 탭바 아이콘 아래 글자, 칩(태그) 안의 글자 등 짧은 레이블에 사용
  static TextStyle get label => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500, // Medium: Regular보다 살짝 굵음
        height: 1.0,
      );
}
