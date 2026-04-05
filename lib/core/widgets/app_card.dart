import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 전체에서 공통으로 사용하는 카드 위젯 모음
//
// 카드란?
//   정보를 시각적으로 묶어서 보여주는 네모난 컨테이너입니다.
//   예) 식당 정보 카드, 주문 내역 카드, 프로필 카드 등
//
// 카드 종류:
//   AppCard         — 기본 카드 (테두리로 구분, 그림자 없음)
//   AppElevatedCard — 그림자 있는 카드 (강조가 필요할 때)
//   AppHighlightCard — primary 색 배경 카드 (특별 강조)
// ══════════════════════════════════════════════════════════


// ─────────────────────────────────────────────────────────
// AppCard: 기본 카드
//
// 사용 예) 식당 목록 항목, 메뉴 항목, 일반 정보 표시
// 흰색 배경 + 연한 회색 테두리로 구분. 그림자 없음(플랫 디자인)
// onTap을 넣으면 탭 가능한 카드가 됨 (리플 효과 포함)
// ─────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,      // 카드 안에 들어갈 내용 (필수)
    this.onTap,               // 탭했을 때 실행할 함수 (없으면 탭 불가)
    this.padding,             // 카드 내부 여백 (미지정 시 16px)
    this.margin,              // 카드 외부 여백 (미지정 시 없음)
    this.backgroundColor,     // 배경색 (미지정 시 흰색)
    this.borderColor,         // 테두리 색 (미지정 시 연한 회색)
    this.borderRadius,        // 모서리 둥글기 (미지정 시 12px)
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    // BorderRadius.circular: 네 모서리를 모두 같은 정도로 둥글게
    final radius = BorderRadius.circular(borderRadius ?? AppRadius.card);

    return Padding(
      padding: margin ?? EdgeInsets.zero, // 외부 여백 적용
      child: Material(
        // Material: 리플(탭할 때 퍼지는 물결 효과) 애니메이션을 위해 필요
        color: backgroundColor ?? AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          // InkWell: 탭했을 때 리플 효과를 보여주는 위젯
          // onTap이 null이면 리플 효과도 없고 탭도 안 됨
          onTap: onTap,
          borderRadius: radius, // 리플도 카드 모양대로 잘리도록
          child: Container(
            padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: borderColor ?? AppColors.divider, // 연한 회색 테두리
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppElevatedCard: 그림자가 있는 강조 카드
//
// 사용 예) 추천 식당 강조 카드, 오늘의 추천 메뉴 등
// 그림자로 카드가 화면 위에 떠 있는 느낌을 줌
//
// [모호한 부분] 그림자 수치(elevation)는 와이어프레임 추정치입니다.
// ─────────────────────────────────────────────────────────
class AppElevatedCard extends StatelessWidget {
  const AppElevatedCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        // withAlpha(20): 검정의 20/255 투명도 = 매우 연한 그림자
        shadowColor: Colors.black.withAlpha(20),
        elevation: 4, // 그림자 높이. 클수록 그림자가 넓고 진해짐
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
            child: child,
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppHighlightCard: primary 색 배경의 강조 카드
//
// 사용 예) AI 추천 결과, 오늘의 세션 요약 등 특별히 주목시키고 싶은 카드
// 배경이 primarySurface(주황의 아주 옅은 색)로 채워짐
// ─────────────────────────────────────────────────────────
class AppHighlightCard extends StatelessWidget {
  const AppHighlightCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // 현재 테마에서 primaryContainer 색을 가져옴
    // 손님앱: FFF5F0 (아주 연한 주황), 점주앱: F0FBF9 (아주 연한 청록)
    final primarySurface = Theme.of(context).colorScheme.primaryContainer;

    // AppCard를 재사용해서 배경색만 바꾼 형태
    return AppCard(
      onTap: onTap,
      backgroundColor: primarySurface,
      borderColor: Colors.transparent, // 테두리 없음 (색 배경으로 구분됨)
      padding: padding,
      child: child,
    );
  }
}
