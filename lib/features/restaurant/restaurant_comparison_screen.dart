import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../services/recommendations_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-14 식당 비교 화면
//
// 진입 경로: CU-11 AI 추천 리스트 → 비교할 식당 2~3개 선택 → 이 화면
//
// 표시 내용:
//   - 선택한 식당들을 가로 스크롤로 나란히 카드 형태로 비교
//   - 비교 항목: 이름 / 카테고리 / 가격대 / 점수 / 주소 / 추천 근거
//
// 선택 개수 제약: 2~3개만 허용 (1개 이하면 비교 무의미, 4개 이상은 UI 복잡)
// ══════════════════════════════════════════════════════════

class RestaurantComparisonScreen extends StatelessWidget {
  const RestaurantComparisonScreen({
    super.key,
    required this.recommendations,
  });

  /// 비교할 추천 결과 (2~3개 권장)
  final List<RecommendationDto> recommendations;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-14');
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: '식당 비교',
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.md,
                AppSpacing.screenHorizontal,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows_rounded,
                      color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${recommendations.length}개 식당 나란히 비교',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── 가로 스크롤 비교 카드 ────────────────────
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                physics: const BouncingScrollPhysics(),
                itemCount: recommendations.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, i) =>
                    _ComparisonCard(rec: recommendations[i], rank: i + 1),
              ),
            ),

            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

// ── 비교 카드 하나 ──────────────────────────────────────
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.rec, required this.rank});

  final RecommendationDto rec;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final priceLabel = rec.priceRange != null
        ? '${_formatComma(rec.priceRange!)}원대'
        : '가격 미정';

    return SizedBox(
      width: 260,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 순위 + 점수
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: AppTextStyles.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '점수 ${rec.score}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // 이름
            Text(
              rec.name,
              style: AppTextStyles.heading3,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const Divider(height: 24),

            // ── 속성 표 ─────────────────────────────────
            _AttrRow(label: '카테고리', value: rec.category ?? '-'),
            const SizedBox(height: 8),
            _AttrRow(label: '가격대', value: priceLabel),
            const SizedBox(height: 8),
            _AttrRow(label: '주소', value: rec.address ?? '-', maxLines: 2),

            const SizedBox(height: AppSpacing.md),

            // ── 추천 근거 ────────────────────────────────
            if (rec.reasons.isNotEmpty) ...[
              Text(
                '추천 근거',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: rec.reasons.map((r) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundGrey,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      r,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

// ── 비교 속성 한 줄 (레이블 + 값) ──────────────────────
class _AttrRow extends StatelessWidget {
  const _AttrRow({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textHint,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodySmall,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
