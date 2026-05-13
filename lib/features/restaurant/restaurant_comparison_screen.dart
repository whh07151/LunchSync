import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/utils/normalizer.dart';
import '../../core/utils/distance_calculator.dart';
import '../../core/debug/debug_toast.dart';
import '../../services/geolocation_service.dart';
import '../../services/recommendations_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-14 식당 비교 화면
//
// 진입 경로: CU-11 AI 추천 리스트 → 비교할 식당 2~3개 선택 → 이 화면
//
// 표시 내용:
//   - 선택한 식당들을 가로 스크롤로 나란히 카드 형태로 비교
//   - 비교 항목: 이름 / 카테고리 / 가격대 / 거리 / 점수 / 주소 / 추천 근거
//
// 선택 개수 제약: 2~3개만 허용 (1개 이하면 비교 무의미, 4개 이상은 UI 복잡)
//
// 거리 표기 정책 (2026-05-13 추가, m7):
//   - 홈/추천/상세 화면이 모두 Haversine 거리를 노출하는데 비교 화면만 누락이라
//     "가까움/멀음" 비교 축이 사라지는 일관성 위반이 있었음.
//   - 화면 진입 시 GPS 스냅샷 1회 조회 → 각 카드에 distanceLabel 결과를 표기.
//   - 권한 거부/위치 서비스 꺼짐 등으로 좌표를 못 얻으면 distanceLabel 이 null 을
//     돌려주므로 거리 줄 자체를 그리지 않음(다른 화면과 동일).
// ══════════════════════════════════════════════════════════

class RestaurantComparisonScreen extends StatefulWidget {
  const RestaurantComparisonScreen({
    super.key,
    required this.recommendations,
  });

  /// 비교할 추천 결과 (2~3개 권장)
  final List<RecommendationDto> recommendations;

  @override
  State<RestaurantComparisonScreen> createState() =>
      _RestaurantComparisonScreenState();
}

class _RestaurantComparisonScreenState
    extends State<RestaurantComparisonScreen> {
  // ── 사용자 현재 위치(거리 표시용) ──────────────────────
  // 화면 진입 시 GPS 1회 스냅샷만 사용. 비교 카드는 짧은 체류 화면이라
  // 스트림이 아닌 1회 조회로 충분(추천 리스트 화면과 동일 패턴).
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-14');
      _loadUserLocation();
    });
  }

  /// 사용자 GPS 스냅샷 1회 조회.
  ///
  /// 실패 케이스(권한 거부, 위치 서비스 꺼짐, 타임아웃)에는 null 그대로 두어
  /// distanceLabel 이 null 을 반환 → 카드의 거리 줄이 자동으로 숨겨짐.
  Future<void> _loadUserLocation() async {
    final pos = await const GeolocationService().getCurrentPosition();
    if (!mounted || pos == null) return;
    setState(() {
      _userLat = pos.latitude;
      _userLng = pos.longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = widget.recommendations;

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
                itemBuilder: (_, i) => _ComparisonCard(
                  rec: recommendations[i],
                  rank: i + 1,
                  userLat: _userLat,
                  userLng: _userLng,
                ),
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
  const _ComparisonCard({
    required this.rec,
    required this.rank,
    required this.userLat,
    required this.userLng,
  });

  final RecommendationDto rec;
  final int rank;

  /// 사용자 현재 좌표(거리 계산용). null 이면 거리 줄을 그리지 않음.
  final double? userLat;
  final double? userLng;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // 가격대 표시는 공통 헬퍼로 통일.
    // price_range 값이 출처별로 의미가 달라(원/1000원 단위/1~5 척도)
    // 단순 출력 시 "13원대" 같은 부자연스러운 문구가 나오는 버그를 정규화로 해결.
    final priceLabel = formatRestaurantPriceRange(rec.priceRange);

    // 거리 라벨 — 사용자 위치/식당 좌표 둘 다 있을 때만 표기.
    // 다른 화면(home/recommendation/detail)과 동일한 정책으로 일관성 확보.
    final distance = distanceLabel(
      userLat: userLat,
      userLng: userLng,
      targetLat: rec.lat,
      targetLng: rec.lng,
    );

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
            // 거리는 좌표가 있을 때만 표시. 다른 화면 정책과 일치(미렌더링).
            if (distance != null) ...[
              const SizedBox(height: 8),
              _AttrRow(label: '거리', value: distance),
            ],
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

  // 가격대 표기는 normalizer.dart 의 formatRestaurantPriceRange 로 통일.
  // 기존의 천단위 콤마 포맷터는 이 화면에서 더 이상 사용하지 않아 제거했음.
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
