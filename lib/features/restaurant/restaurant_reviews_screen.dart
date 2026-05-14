import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/components/components.dart';
import '../../providers/user_provider.dart';
import '../../services/reviews_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 매장별 별점/리뷰 리스트 화면 (배민 패턴 — 2026-05-15 발전)
//
// 진입 경로:
//   - 사장 어플 owner_home_screen → 매장 평점 카드 클릭
//   - 손님 어플 restaurant_detail_screen → 평점 칩 클릭 (옵션)
//
// 데이터 소스:
//   GET /api/restaurants/:id/reviews
//   → { averageScore, count, reviews: ReviewDto[] }
//
// UI 구성:
//   1. 평균 평점 헤더 (큰 별 + 점수 + 리뷰 개수)
//   2. 리뷰 리스트 (별점 + 본문 + 작성자 이니셜 + 상대 시간)
//   3. 빈 상태 / 로딩 / 에러 상태 분기 (AppEmptyState 일관성)
//
// 디자인 토큰:
//   - amber 600 — 별점 표준색 (디자인 시스템에 이미 사용 중)
//   - AppColors / AppTextStyles / AppRadius / AppSpacing 만 사용
// ══════════════════════════════════════════════════════════

class RestaurantReviewsScreen extends ConsumerStatefulWidget {
  const RestaurantReviewsScreen({
    super.key,
    required this.restaurantId,
    this.restaurantName,
  });

  /// 리뷰를 조회할 매장 ID
  final String restaurantId;

  /// AppBar 타이틀에 표시할 매장명 (optional — 없으면 "리뷰" 단독 표시)
  final String? restaurantName;

  @override
  ConsumerState<RestaurantReviewsScreen> createState() =>
      _RestaurantReviewsScreenState();
}

class _RestaurantReviewsScreenState
    extends ConsumerState<RestaurantReviewsScreen> {
  static const _api = ReviewsApiService();

  RestaurantReviewsResult? _result;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요해요';
      });
      return;
    }

    final result = await _api.getReviewsByRestaurant(
      accessToken: token,
      restaurantId: widget.restaurantId,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _isLoading = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: widget.restaurantName != null
            ? '${widget.restaurantName} 리뷰'
            : '리뷰',
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          AppEmptyState(
            icon: Icons.error_outline,
            title: '리뷰를 불러오지 못했어요',
            description: _error!,
          ),
        ],
      );
    }

    final result = _result ?? RestaurantReviewsResult.empty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      children: [
        _buildAverageHeader(result),
        const SizedBox(height: AppSpacing.lg),
        if (result.reviews.isEmpty)
          _buildEmpty()
        else ...[
          // 리뷰 목록 — 최신순(백엔드 정렬)
          for (final r in result.reviews) ...[
            _ReviewTile(review: r),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }

  // ── 평균 평점 헤더 ───────────────────────────────────────
  // 큰 숫자 + 5개 별 상태 + 리뷰 총 개수.
  // 리뷰 0건이면 "아직 리뷰가 없습니다" 한 줄로 단순 표시 (Empty 패턴 분리).
  Widget _buildAverageHeader(RestaurantReviewsResult result) {
    final amber = Colors.amber.shade600;
    final avg = result.averageScore;
    final hasReviews = result.count > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                hasReviews ? avg.toStringAsFixed(1) : '-',
                style: AppTextStyles.heading1.copyWith(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: hasReviews ? amber : AppColors.textHint,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${result.count}개 리뷰',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            width: 1,
            height: 60,
            color: AppColors.divider,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 평균 별 표시 (반올림 1자리 — 시각 보조)
                Row(
                  children: List.generate(5, (i) {
                    final filled = hasReviews && (i + 1) <= avg.round();
                    return Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: filled ? amber : AppColors.iconInactive,
                      size: 22,
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  hasReviews
                      ? '손님들이 남긴 솔직 후기'
                      : '아직 받은 리뷰가 없어요',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: AppEmptyState(
        icon: Icons.rate_review_outlined,
        title: '아직 리뷰가 없습니다',
        description: '첫 후기를 기다리고 있어요',
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 리뷰 1건 카드 — 별 + 본문 + 작성자 이니셜 + 상대 시간
// ══════════════════════════════════════════════════════════

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final ReviewDto review;

  @override
  Widget build(BuildContext context) {
    final amber = Colors.amber.shade600;
    final initial = _initialOf(review.userName);
    final relativeTime = _relativeTime(review.reviewAt);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 작성자 이니셜 아바타 — Member avatar 컴포넌트 흉내내지 않고
              // 단순 CircleAvatar 로 가벼운 표현(앱 디자인 토큰 내).
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.backgroundGrey,
                child: Text(
                  initial,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maskName(review.userName),
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      relativeTime,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 별점 (작은 별 5개)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = (i + 1) <= review.score;
                  return Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: filled ? amber : AppColors.iconInactive,
                    size: 16,
                  );
                }),
              ),
            ],
          ),
          // 리뷰 본문 — 빈 문자열일 땐 노출 안 함
          if (review.text != null && review.text!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.text!,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  /// 이름의 첫 글자(공백 제거) — '?' 폴백.
  String _initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    // 한글/영문 모두 첫 글자만.
    return trimmed.characters.first;
  }

  /// 이름 마스킹 — 개인정보 보호. 첫 글자 + '*'.
  /// 예: "홍길동" → "홍**"  /  "박" → "박"
  String _maskName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '익명';
    if (t.length == 1) return t;
    return '${t.characters.first}${'*' * (t.length - 1).clamp(0, 3)}';
  }

  /// "방금 전" / "12분 전" / "3시간 전" / "5일 전" / 그 이상은 yyyy.MM.dd.
  String _relativeTime(DateTime at) {
    final now = DateTime.now();
    final diff = now.difference(at);

    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';

    // 7일 이상은 절대 날짜로.
    final y = at.year.toString().padLeft(4, '0');
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }
}
