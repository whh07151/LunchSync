// ══════════════════════════════════════════════════════════
// 파일 역할: WOW 포인트 #3 "점심 케미 매트릭스" 카드 위젯
//
// 표시 형태:
//   ┌─────────────────────────────────────────────┐
//   │ 📊 당신들의 케미는                          │
//   │                                              │
//   │     87점  매콤+가성비형                      │
//   │                                              │
//   │     [한식]  [분식]  [중식]                    │
//   └─────────────────────────────────────────────┘
//
// 색상 톤 (백엔드 tone 필드 분기):
//   warm    : 따뜻한 주황 그라데이션 (한식/매콤 그룹)
//   cool    : 시원한 청록 그라데이션 (일식/샐러드/카페 그룹)
//   neutral : 회색 그라데이션 (데이터 부족 / 기타)
//
// 사용처:
//   RecommendationListScreen 의 상단 안내 배너 바로 아래.
//   데이터 로딩 중 → 스켈레톤 박스. null → 위젯 자체 미노출 (장애 차단).
// ══════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../../services/sessions_api_service.dart' show ChemistryResult;

class ChemistryCard extends StatelessWidget {
  const ChemistryCard({
    super.key,
    required this.result,
  });

  final ChemistryResult result;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(result.tone);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.bgStart, palette.bgEnd],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border, width: 1),
          // 가벼운 그림자 — 카드가 떠있는 느낌을 살짝만.
          boxShadow: [
            BoxShadow(
              color: palette.border.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 헤더: 아이콘 + 안내 카피 ─────────────────
            Row(
              children: [
                Text(
                  '📊',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  '당신들의 케미는',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── 본문: 점수 + 라벨 한 줄 ─────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 점수 — 톤 색상 강조. 큰 글씨로 시연 임팩트.
                Text(
                  '${result.score}점',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: palette.accent,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 10),
                // 라벨 — 한 줄 요약. 점수 옆 베이스라인 정렬.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      result.label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            // ── 카테고리 칩 (없으면 영역 자체 미노출) ───
            if (result.topCategories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: result.topCategories
                    .map(
                      (cat) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: palette.chipBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: palette.chipBorder),
                        ),
                        child: Text(
                          cat,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 톤에 따른 팔레트 묶음. 색상 디자인 변경 시 이 함수만 손보면 됨.
  _ChemistryPalette _palette(String tone) {
    switch (tone) {
      case 'warm':
        return const _ChemistryPalette(
          bgStart: Color(0xFFFFF5F0),
          bgEnd: Color(0xFFFFE8DA),
          border: Color(0xFFFFAD72),
          accent: Color(0xFFE67A30),
          textPrimary: Color(0xFF1A1A1A),
          textSecondary: Color(0xFF8C5A38),
          chipBg: Color(0xFFFFFFFF),
          chipBorder: Color(0xFFFFD9BD),
        );
      case 'cool':
        return const _ChemistryPalette(
          bgStart: Color(0xFFF0FBF9),
          bgEnd: Color(0xFFD9F4EE),
          border: Color(0xFF4ECFBB),
          accent: Color(0xFF189E88),
          textPrimary: Color(0xFF1A1A1A),
          textSecondary: Color(0xFF356A60),
          chipBg: Color(0xFFFFFFFF),
          chipBorder: Color(0xFFB6E8DE),
        );
      case 'neutral':
      default:
        return const _ChemistryPalette(
          bgStart: Color(0xFFFAFAFA),
          bgEnd: Color(0xFFEFEFEF),
          border: Color(0xFFCCCCCC),
          accent: Color(0xFF555555),
          textPrimary: Color(0xFF1A1A1A),
          textSecondary: Color(0xFF666666),
          chipBg: Color(0xFFFFFFFF),
          chipBorder: Color(0xFFE0E0E0),
        );
    }
  }
}

// ── 케미 카드 스켈레톤 (로딩 중) ──────────────────────────
// 결과가 도착하기 전까지 표시. 시연에서 화면이 텅 비어 보이는 인상을 차단.
class ChemistryCardSkeleton extends StatelessWidget {
  const ChemistryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
      ),
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          color: AppColors.backgroundGrey,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

// 내부 팔레트 묶음 — 톤별 색 7종. private.
class _ChemistryPalette {
  const _ChemistryPalette({
    required this.bgStart,
    required this.bgEnd,
    required this.border,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.chipBg,
    required this.chipBorder,
  });

  final Color bgStart;
  final Color bgEnd;
  final Color border;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color chipBg;
  final Color chipBorder;
}
