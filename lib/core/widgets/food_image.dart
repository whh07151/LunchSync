// ══════════════════════════════════════════════════════════
// 파일 역할: 메뉴 / 식당 사진을 안전하게 렌더링하는 공용 위젯 모음
//
// 왜 이 파일이 필요한가? (사장님 피드백 대응)
//   - "음식 메뉴에 사진도 잘 보였으면 좋겠고" — POS 사장님 인터뷰(05-13).
//   - 기존 menu_screen.dart 는 imageUrl 이 DB 에 있어도 Image.network 자체를
//     호출하지 않고 항상 음식 아이콘만 그렸음 → 사진이 화면에 절대 안 나옴.
//   - 식당 상세 화면(CU-13) 도 대표 이미지를 한 번도 그리지 않음.
//   - 또한 일부 menu_items.image_url 은 빈 문자열("") 이거나 http:// 만
//     반환되는 경우가 있어 단순히 Image.network 만 호출하면 회색 사각형이
//     나오거나 web mixed-content 차단으로 X 아이콘이 나오는 케이스가 있음.
//
// 어떻게 해결하는가?
//   1) imageUrl 이 비어있으면(null / "") 즉시 카테고리별 fallback 박스로 전환.
//   2) Image.network 에 errorBuilder + loadingBuilder 를 항상 함께 지정.
//   3) errorBuilder 가 발화하면 동일한 카테고리 fallback 박스로 graceful 대체.
//   4) fallback 박스는 디자인 토큰(AppColors / primary) 의 연한 톤 배경 +
//      카테고리 이모지 큰 글씨 1개로 통일감 유지(이미지 에셋 추가 0건).
//
// 사용처:
//   - lib/features/menu/menu_screen.dart                    (메뉴 카드 썸네일)
//   - lib/features/restaurant/restaurant_detail_screen.dart (식당 헤더 + 미리보기)
//
// 디자인 규칙:
//   - 색상 토큰 변경 금지. primary.withAlpha(15) 톤 + AppColors.textSecondary.
//   - 이모지 1자만 사용(폰트 미설치 환경에서도 안전).
//   - 모서리 둥글기는 AppRadius.card 통일.
// ══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// 메뉴 / 식당 카테고리 → fallback 이모지 매핑
///
/// 백엔드 카테고리 문자열은 한글이 기본(mapMenuCategory 결과)이고,
/// 영어가 섞여올 수도 있어 lowercase 비교를 함께 수행한다.
/// 매칭이 안 되면 🍽️ 로 폴백.
String resolveFoodEmoji(String? category) {
  if (category == null || category.trim().isEmpty) return '🍽️';
  final raw = category.trim();
  final lower = raw.toLowerCase();

  // ── 한식 ─────────────────────────────────────────────
  if (raw.contains('한식') || raw.contains('밥') || raw.contains('정식') ||
      lower.contains('korean') || lower.contains('rice')) {
    return '🍚';
  }
  // ── 일식 / 면류 ──────────────────────────────────────
  // 면류는 카테고리 자체가 일식이 아니어도 면 형태이므로 면 이모지로.
  if (raw.contains('일식') || raw.contains('초밥') || raw.contains('스시') ||
      lower.contains('japanese') || lower.contains('sushi')) {
    return '🍣';
  }
  if (raw.contains('면') || raw.contains('국수') || raw.contains('라면') ||
      lower.contains('noodle') || lower.contains('ramen')) {
    return '🍜';
  }
  // ── 중식 ─────────────────────────────────────────────
  if (raw.contains('중식') || raw.contains('짜장') || raw.contains('짬뽕') ||
      lower.contains('chinese')) {
    return '🥢';
  }
  // ── 양식 ─────────────────────────────────────────────
  if (raw.contains('양식') || raw.contains('파스타') || raw.contains('스테이크') ||
      lower.contains('western') || lower.contains('pasta')) {
    return '🍝';
  }
  // ── 분식 ─────────────────────────────────────────────
  if (raw.contains('분식') || raw.contains('떡볶이') || raw.contains('김밥') ||
      lower.contains('snack')) {
    return '🍢';
  }
  // ── 카페 / 음료 / 디저트 ─────────────────────────────
  if (raw.contains('카페') || raw.contains('커피') || raw.contains('디저트') ||
      raw.contains('음료') ||
      lower.contains('cafe') || lower.contains('coffee') ||
      lower.contains('drink') || lower.contains('beverage') ||
      lower.contains('dessert')) {
    return '☕';
  }
  // ── 패스트푸드 / 햄버거 ──────────────────────────────
  if (raw.contains('버거') || raw.contains('패스트') ||
      lower.contains('burger') || lower.contains('fast')) {
    return '🍔';
  }
  // ── 아시안 (베트남, 태국 등) ─────────────────────────
  if (raw.contains('아시안') || raw.contains('베트남') || raw.contains('쌀국수') ||
      raw.contains('태국') || raw.contains('인도') ||
      lower.contains('asian') || lower.contains('thai') ||
      lower.contains('vietnam')) {
    return '🍜';
  }
  // ── 추천(special) 같이 의미는 있지만 음식 종류가 아닌 경우 ──
  if (raw.contains('추천') || lower.contains('recommend')) {
    return '⭐';
  }
  // ── 기타 ─────────────────────────────────────────────
  return '🍽️';
}

/// imageUrl 이 "보낼 수 있는 값"인지 사전 검증.
///
/// 빈 문자열, 공백, "null" 문자열, 잘못된 스킴(file://, data: 등) 등은
/// Image.network 호출 자체를 막아 회색 사각형이 뜨는 비용을 줄임.
bool _isUsableNetworkUrl(String? url) {
  if (url == null) return false;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.toLowerCase() == 'null') return false;
  // http(s) 만 허용. 웹에서는 http 도 mixed-content 로 차단될 수 있지만,
  // 모바일에서는 정상이고 errorBuilder 가 받아주므로 시도는 허용.
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

/// 메뉴/식당 공통 음식 이미지 위젯.
///
/// imageUrl 이 비어있거나 로드 실패 시 categoryLabel 기반 이모지 박스를
/// 출력해 디자인 일관성을 유지한다. emojiSize 만 외부에서 조정 가능.
class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.imageUrl,
    required this.categoryLabel,
    this.width = 88,
    this.height = 88,
    this.borderRadius,
    this.emojiSize = 36,
    this.semanticLabel,
  });

  /// 백엔드에서 받은 사진 URL. null / 빈 문자열이면 즉시 fallback.
  final String? imageUrl;

  /// 카테고리 라벨 — fallback 이모지를 고르는 키. 예: "한식", "음료".
  final String? categoryLabel;

  /// 표시 영역 너비 / 높이. 정사각형(메뉴 썸네일) 또는 와이드(식당 헤더)에 모두 대응.
  final double width;
  final double height;

  /// 모서리 둥글기. null 이면 AppRadius.card 사용.
  final BorderRadius? borderRadius;

  /// fallback 이모지 폰트 크기. 큰 영역(헤더)에서는 60+ 로 키워 사용.
  final double emojiSize;

  /// 접근성 라벨 — 음식 이름 등을 전달하면 스크린리더가 읽어준다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.card);
    final primary = Theme.of(context).colorScheme.primary;

    // ── 1) 사용 불가능한 URL: 바로 fallback ───────────────
    if (!_isUsableNetworkUrl(imageUrl)) {
      return _buildFallback(primary, radius);
    }

    // ── 2) Image.network 시도 + 안전 빌더들 ─────────────────
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl!.trim(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        // 로딩 중: 같은 사이즈 박스 안에서 가벼운 인디케이터.
        // 스켈레톤 라이브러리 추가 없이도 자리는 차지하므로 UI 점프 방지.
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: AppColors.backgroundGrey,
            alignment: Alignment.center,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: primary.withAlpha(120),
              ),
            ),
          );
        },
        // 에러(404, mixed-content, CORS 등): 카테고리 fallback 으로 graceful 대체.
        // 회색 X 아이콘이 노출되는 걸 완전히 차단해 사장님 우려를 해소.
        errorBuilder: (context, error, stack) {
          return _buildFallback(primary, radius);
        },
      ),
    );
  }

  // ── fallback 박스 (이모지 1자 + 연한 primary 배경) ───────
  // 색상 토큰 변경 없음. primary.withAlpha(15) = AppColors.background 위
  // 메뉴 카드 영역과 동일한 톤(menu_screen 기존 톤과 일치).
  Widget _buildFallback(Color primary, BorderRadius radius) {
    final emoji = resolveFoodEmoji(categoryLabel);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // 연한 주황 배경 — 기존 메뉴 카드 placeholder 와 동일 톤
        color: primary.withAlpha(15),
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        // 이모지는 fontSize 만으로 충분히 표현됨. 폰트 패밀리는 시스템 기본 사용.
        style: TextStyle(
          fontSize: emojiSize,
          // 텍스트 베이스라인 약간 위로: 박스 가운데 시각 정렬을 위해
          height: 1.0,
        ),
      ),
    );
  }
}
