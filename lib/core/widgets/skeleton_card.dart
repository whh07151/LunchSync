// ══════════════════════════════════════════════════════════
// 파일 역할: 데이터 로딩 중 표시되는 식당 카드 스켈레톤(placeholder)
//
// 왜 필요한가?
//   - 빈 카드(아이콘 1개)나 단순 스피너는 페이지 점프가 커서
//     사용자가 "앱이 멈췄나?" 라고 느낄 수 있음.
//   - 실제 카드와 같은 크기의 회색 박스를 미리 그려두면
//     데이터 도착 시 자연스럽게 콘텐츠로 대체돼 체감 속도가 올라감.
//
// 의존성:
//   - shimmer 패키지를 도입하지 않고 단색 회색 박스만으로 구성.
//     (pubspec.yaml 추가 시 다른 의존성과 버전 충돌 가능성이 있어 회피)
//   - AppColors.divider / AppColors.surface / AppColors.border 만 사용해
//     디자인 토큰 위반 없음.
//
// 사용처:
//   - lib/features/home/home_screen.dart  (AI 추천 식당 가로 스크롤 로딩 상태)
//
// ⚠️ 디자인 토큰/위젯 구조 변경 없음 — 기존 _buildRestaurantSkeleton 의 모양 그대로
//    공용 위젯으로만 분리해 재사용 가능하게 만든 것.
// ══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// 식당 카드 한 장 크기의 스켈레톤(placeholder) 위젯.
///
/// 홈 화면 AI 추천 가로 스크롤 영역에서 사용하는 카드와
/// 동일한 너비/높이/모서리 반경을 가지도록 설계.
/// 데이터 로드가 완료되면 호출자가 실제 카드로 교체.
class RestaurantSkeletonCard extends StatelessWidget {
  const RestaurantSkeletonCard({super.key});

  // 식당 카드 내부 콘텐츠 너비(150) — 실제 카드(_buildRestaurantCard) 와 동일.
  static const double _kInnerWidth = 150;

  // 이미지 영역 높이(72) — 실제 카드 placeholder 이미지와 동일.
  static const double _kImageHeight = 72;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: SizedBox(
        width: _kInnerWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 이미지 placeholder ────────────────────────
            // 실제 카드의 식당 이미지 영역과 같은 크기·모서리.
            Container(
              height: _kImageHeight,
              decoration: BoxDecoration(
                // divider 색에 50% 알파를 곱해 살짝 연한 회색.
                // 단순 backgroundGrey 단일 톤보다 텍스트 placeholder 와
                // 살짝 대비가 나서 카드처럼 인식됨.
                color: AppColors.divider.withAlpha(140),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // ── 텍스트 placeholder 바 3개 ─────────────────
            // 이름(긴 바) → 카테고리(중간 바) → 가격/거리(짧은 바) 순.
            _bar(width: 110, height: 12),
            const SizedBox(height: 6),
            _bar(width: 70, height: 10),
            const Spacer(),
            _bar(width: 50, height: 12),
          ],
        ),
      ),
    );
  }

  /// 회색 박스 한 줄 — 텍스트 placeholder 용.
  /// 단색 divider 톤 + 모서리 살짝(4px) 둥글게.
  Widget _bar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.divider.withAlpha(140),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
