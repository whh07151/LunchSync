import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_spacing.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: Flutter 앱 전체의 시각적 테마(테마 = 앱의 디자인 규칙)를 생성하는 파일
//
// ThemeData란?
//   Flutter에서 버튼, 텍스트, 입력창 등 모든 UI 요소의 기본 모양을
//   한 번에 설정하는 객체입니다.
//   ThemeData를 MaterialApp에 넣으면 앱 전체에 자동으로 적용됩니다.
//
// 손님앱 vs 점주앱 분리 방법:
//   AppType.customer → 주황색 테마
//   AppType.owner    → 청록색 테마
//   → AppTheme.of(AppType.customer) 처럼 호출해서 사용합니다.
//
// TODO: 상태 관리 라이브러리가 결정되면 AppType 전환 로직을 추가합니다.
//       현재는 main.dart에서 수동으로 지정합니다.
// ══════════════════════════════════════════════════════════

/// 앱 종류를 구분하는 열거형(enum)
/// customer = 손님앱, owner = 점주앱
enum AppType { customer, owner }

class AppTheme {
  AppTheme._();

  /// AppType에 따라 적절한 ThemeData를 반환하는 정적 메서드
  /// 사용 예) AppTheme.of(AppType.customer)
  static ThemeData of(AppType type) {

    // 앱 타입에 따라 색상 선택
    final primary = type == AppType.customer
        ? CustomerColors.primary       // 손님앱: 주황
        : OwnerColors.primary;         // 점주앱: 청록

    final primaryDark = type == AppType.customer
        ? CustomerColors.primaryDark
        : OwnerColors.primaryDark;

    final primarySurface = type == AppType.customer
        ? CustomerColors.primarySurface
        : OwnerColors.primarySurface;

    return ThemeData(
      // useMaterial3: Flutter 최신 디자인 가이드라인(Material 3) 적용
      useMaterial3: true,

      // ── 색상 체계 ────────────────────────────────────────
      // ColorScheme: 앱 전체의 색상 관계를 정의하는 객체
      // Flutter 위젯들이 이 색상을 참조해서 자동으로 색을 결정합니다
      colorScheme: ColorScheme.light(
        primary: primary,              // 주요 강조색 (버튼, 활성 탭 등)
        onPrimary: Colors.white,       // primary 위에 올라오는 텍스트/아이콘 색
        primaryContainer: primarySurface, // primary의 옅은 배경색
        surface: AppColors.surface,    // 카드, 팝업 등의 배경색
        onSurface: AppColors.textPrimary, // surface 위의 텍스트 색
        error: AppColors.error,        // 오류 상태 색상
        outline: AppColors.border,     // 테두리 색상
      ),

      // 화면 전체 배경색
      scaffoldBackgroundColor: AppColors.background,

      // ── 텍스트 테마 ──────────────────────────────────────
      // 앱 전체의 기본 글자 스타일을 설정
      // Noto Sans 폰트를 기반으로, 각 역할별 스타일을 연결
      textTheme: GoogleFonts.notoSansTextTheme().copyWith(
        displayLarge: AppTextStyles.heading1,
        displayMedium: AppTextStyles.heading2,
        headlineMedium: AppTextStyles.heading3,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
        labelLarge: AppTextStyles.buttonLarge,
        labelMedium: AppTextStyles.label,
        labelSmall: AppTextStyles.caption,
      ),

      // ── 앱바(상단 타이틀 바) 기본 스타일 ─────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background, // 앱바 배경: 흰색
        foregroundColor: AppColors.textPrimary, // 앱바 텍스트/아이콘: 거의 검정
        elevation: 0,                           // 그림자 없음 (플랫한 디자인)
        scrolledUnderElevation: 0,              // 스크롤해도 그림자 생기지 않음
        centerTitle: false,                     // 제목을 왼쪽 정렬
        titleTextStyle: AppTextStyles.heading3, // 앱바 제목 글자 스타일
        // 상단 상태바(시간, 배터리 표시줄) 아이콘을 어두운 색으로
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ── 주요(Elevated) 버튼 기본 스타일 ─────────────────
      // ElevatedButton: 배경색이 채워진 주요 버튼 (예: "시작하기", "다음")
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,              // 버튼 배경색: primary
          foregroundColor: Colors.white,         // 버튼 텍스트/아이콘: 흰색
          disabledBackgroundColor: AppColors.disabled,    // 비활성화 배경
          disabledForegroundColor: Colors.white,          // 비활성화 텍스트
          elevation: 0,                          // 그림자 없음
          shadowColor: Colors.transparent,       // 그림자 색도 투명으로
          minimumSize: const Size(double.infinity, 52), // 최소 크기: 가로 꽉 참, 높이 52
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button), // 알약 모양
          ),
          textStyle: AppTextStyles.buttonLarge,
        ),
      ),

      // ── 보조(Outlined) 버튼 기본 스타일 ─────────────────
      // OutlinedButton: 테두리만 있는 보조 버튼 (예: "건너뛰기", "취소")
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,                       // 텍스트 색: primary
          side: BorderSide(color: primary, width: 1.5),   // 테두리: primary 색, 1.5px
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppTextStyles.buttonLarge,
        ),
      ),

      // ── 텍스트 버튼 기본 스타일 ──────────────────────────
      // TextButton: 배경/테두리 없이 텍스트만 있는 버튼 (예: "나중에 하기")
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: AppTextStyles.buttonMedium,
        ),
      ),

      // ── 입력 필드 기본 스타일 ────────────────────────────
      // TextField, TextFormField 등 모든 입력창에 자동 적용됨
      inputDecorationTheme: InputDecorationTheme(
        filled: true,                              // 배경색 채우기 활성화
        fillColor: AppColors.backgroundGrey,       // 입력창 배경: 아주 연한 회색
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,               // 좌우 안쪽 여백 16px
          vertical: AppSpacing.sm + 4,             // 상하 안쪽 여백 12px
        ),
        // 기본 테두리
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        // 활성 상태(입력 중이 아닐 때) 테두리
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        // 포커스 상태(입력 중일 때) 테두리 — 더 진한 색으로 강조
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: primaryDark, width: 1.5),
        ),
        // 오류 상태 테두리
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
        labelStyle: AppTextStyles.bodyMedium,
      ),

      // ── 카드 기본 스타일 ─────────────────────────────────
      // Card 위젯에 자동 적용됨
      cardTheme: CardThemeData(
        color: AppColors.surface,       // 카드 배경: 흰색
        elevation: 0,                   // 그림자 없음 (테두리로 구분)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card), // 둥근 모서리
          side: const BorderSide(color: AppColors.divider),    // 연한 회색 테두리
        ),
        margin: EdgeInsets.zero,        // 카드 바깥 여백 없음 (직접 제어)
      ),

      // ── 하단 탭바 기본 스타일 ────────────────────────────
      // BottomNavigationBar 위젯에 자동 적용됨
      // 손님앱 하단의 홈/세션/주문/내역/내정보 탭
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.background,     // 탭바 배경: 흰색
        selectedItemColor: primary,                // 선택된 탭: primary 색
        unselectedItemColor: AppColors.iconInactive, // 선택 안 된 탭: 회색
        showUnselectedLabels: true,                // 선택 안 된 탭도 라벨 표시
        selectedLabelStyle: AppTextStyles.label.copyWith(color: primary),
        unselectedLabelStyle: AppTextStyles.label.copyWith(
          color: AppColors.iconInactive,
        ),
        type: BottomNavigationBarType.fixed,       // 탭 개수가 많아도 고정 크기
        elevation: 0,                              // 탭바 위 그림자 없음
      ),

      // ── 구분선 기본 스타일 ───────────────────────────────
      // Divider 위젯에 자동 적용됨 (리스트 항목 사이 구분선 등)
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,  // 연한 회색
        thickness: 1,              // 두께 1px
        space: 0,                  // 구분선 위아래 추가 여백 없음
      ),

      // ── 칩(Chip) 기본 스타일 ─────────────────────────────
      // Chip, FilterChip 위젯 등에 자동 적용됨
      // 예: 음식 카테고리 필터 태그, 조건 태그 등
      chipTheme: ChipThemeData(
        backgroundColor: primarySurface,  // 칩 배경: primary의 아주 연한 색
        selectedColor: primary,           // 선택된 칩 배경: primary
        labelStyle: AppTextStyles.label,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip), // 많이 둥근 모양
        ),
        side: BorderSide.none,            // 테두리 없음
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 4,  // 좌우 안쪽 여백 12px
          vertical: AppSpacing.xs,        // 상하 안쪽 여백 4px
        ),
      ),
    );
  }
}
