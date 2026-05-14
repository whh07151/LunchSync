import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/utils/normalizer.dart';
import '../../core/utils/distance_calculator.dart';
import '../../core/debug/debug_toast.dart';
import '../../models/restaurant.dart';
import '../../services/geolocation_service.dart';
import '../../services/recommendations_api_service.dart';
import '../decide/decide_screen.dart';

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
//
// 미니게임 진입점 (2026-05-14 추가):
//   - AppBar action 에 🎲 IconButton 노출 → DecideScreen 으로 push.
//   - 비교 후보 2~3개를 그대로 Restaurant 모델로 변환해 전달.
//   - sessionId + isHost 가 함께 넘어오면 DecideScreen 이 votes API 자동 호출.
// ══════════════════════════════════════════════════════════

class RestaurantComparisonScreen extends StatefulWidget {
  const RestaurantComparisonScreen({
    super.key,
    required this.recommendations,
    this.sessionId,
    this.isHost = false,
  });

  /// 비교할 추천 결과 (2~3개 권장)
  final List<RecommendationDto> recommendations;

  /// 미니게임(DecideScreen) 으로 넘길 세션 UUID — votes API 자동 호출 대상.
  /// null 이면 DecideScreen 이 레거시 fallback(단순 pop) 모드로 동작.
  final String? sessionId;

  /// 현재 사용자가 세션 호스트인지 — DecideScreen 의 buttonLabel · API 분기에 사용.
  final bool isHost;

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

  // ── RecommendationDto → Restaurant 변환 ──────────────────
  //
  // DecideScreen 은 공용 Restaurant 모델을 받음. RecommendationDto 의
  // 필드를 최소 변환 — 룰렛/사다리는 name 만 표시하지만 결과 _WinnerCard 가
  // 카테고리 라벨/가격대/평점/이미지 fallback 을 사용하므로 모두 채워준다.
  Restaurant _recToRestaurant(RecommendationDto rec) {
    return Restaurant(
      id: rec.restaurantId,
      name: rec.name,
      category: _categoryFromKorean(rec.category),
      description: rec.reasons.join(', '),
      tags: const [],
      address: rec.address,
      // 가격대는 출처별 단위 혼재 대응을 위해 공용 헬퍼로 정규화.
      priceRange: formatRestaurantPriceRange(rec.priceRange),
    );
  }

  // ── 한글 카테고리 → RestaurantCategory enum 매핑 ─────────
  // 시드/크롤 카테고리 문자열을 모델 enum 으로 변환. 매칭 실패 시 etc.
  // (recommendation_list_screen 의 _categoryFromKorean 과 동일 로직)
  RestaurantCategory _categoryFromKorean(String? korean) {
    if (korean == null) return RestaurantCategory.etc;
    if (korean.contains('한식')) return RestaurantCategory.korean;
    if (korean.contains('중식') || korean.contains('중국')) {
      return RestaurantCategory.chinese;
    }
    if (korean.contains('일식') || korean.contains('일본')) {
      return RestaurantCategory.japanese;
    }
    if (korean.contains('양식') ||
        korean.contains('이탈리') ||
        korean.contains('파스타')) {
      return RestaurantCategory.western;
    }
    if (korean.contains('분식')) return RestaurantCategory.snack;
    if (korean.contains('카페') || korean.contains('디저트')) {
      return RestaurantCategory.cafe;
    }
    return RestaurantCategory.etc;
  }

  // ── 미니게임(DecideScreen) 으로 진입 ───────────────────
  //
  // 비교 화면 AppBar 의 🎲 IconButton 에서 호출.
  // 비교 후보 그대로 Restaurant 모델로 변환 후 sessionId/isHost 와 함께 전달.
  // DecideScreen 내부에서 votes API 자동 호출 + 호스트 케이스 자동 라우팅.
  Future<void> _openDecideGame() async {
    final selected = widget.recommendations
        .map(_recToRestaurant)
        .toList(growable: false);

    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('미니게임은 2개 이상부터 가능해요')),
      );
      return;
    }

    final winner = await Navigator.of(context).push<Restaurant>(
      MaterialPageRoute(
        builder: (_) => DecideScreen(
          candidates: selected,
          sessionId: widget.sessionId,
          isHost: widget.isHost,
        ),
      ),
    );

    if (!mounted || winner == null) return;
    // 비호스트 — castVote 만 등록 후 돌아옴. 부모(추천 리스트) 까지 pop 으로
    // 한 번 더 전파해 흐름이 자연스럽게 추천 화면으로 복귀하도록 한다.
    if (!widget.isHost) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendations = widget.recommendations;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: '식당 비교',
        // 미니게임 진입점 — 비교 후보 2~3개 그대로 룰렛/사다리로 넘기는 단축 동선.
        // tooltip + 카지노 아이콘 + 친근 카피로 발견성 강화.
        actions: [
          IconButton(
            icon: const Icon(Icons.casino_rounded),
            color: AppColors.textPrimary,
            tooltip: '미니게임으로 고르기',
            onPressed: _openDecideGame,
          ),
        ],
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
