import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/recommendations_api_service.dart';
import '../../services/sessions_api_service.dart';
import '../restaurant/restaurant_detail_screen.dart';
import '../restaurant/restaurant_comparison_screen.dart';
import 'recommendation_map_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-11 AI 추천 리스트 화면
//
// 진입 경로: 세션 로비(CU-10) → "AI 추천 보기" 버튼
//
// 표시 내용:
//   - 세션 멤버 전원의 조건(예산/알레르기/비선호/최근식사)을 기반으로
//     백엔드 CORE-07/08 엔진이 계산한 추천 식당 상위 10개
//   - 각 카드에 이름 / 카테고리 / 가격대 / 점수 배지 / 추천 근거 태그
//
// 연동 API: GET /api/sessions/:id/recommendations
//
// 투표 화면 연결은 팀원 담당 영역 — 이 화면에서는 리스트 표시까지만.
// ══════════════════════════════════════════════════════════

class RecommendationListScreen extends ConsumerStatefulWidget {
  const RecommendationListScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  final String sessionId;
  final String sessionName;

  @override
  ConsumerState<RecommendationListScreen> createState() =>
      _RecommendationListScreenState();
}

class _RecommendationListScreenState
    extends ConsumerState<RecommendationListScreen> {
  static const _api = RecommendationsApiService();

  List<RecommendationDto>? _recommendations;
  bool _isLoading = true;
  String? _errorMessage;

  // 비교 모드 상태: true면 카드가 체크박스로 바뀌고 선택된 항목을 모음.
  // 선택 개수 2~3개일 때만 "비교하기" 버튼이 활성화됨.
  bool _isCompareMode = false;
  final Set<String> _selectedForCompare = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebugToast.show(context, 'CU-11');
      _loadRecommendations();
    });
  }

  // ── 추천 목록 조회 ─────────────────────────────────────
  // 에러 케이스:
  //   - 토큰 없음 → 로그아웃 상태 (일반적으로 도달 안 됨)
  //   - 네트워크 실패 → 빈 리스트 반환되면 "추천 없음" 상태 표시
  Future<void> _loadRecommendations() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '로그인이 필요합니다.';
      });
      return;
    }

    final list = await _api.getRecommendations(
      accessToken: token,
      sessionId: widget.sessionId,
    );

    if (!mounted) return;
    setState(() {
      _recommendations = list;
      _isLoading = false;
    });
  }

  // 비교 모드 토글: 켜지면 선택 초기화
  void _toggleCompareMode() {
    setState(() {
      _isCompareMode = !_isCompareMode;
      _selectedForCompare.clear();
    });
  }

  // 카드 탭 처리 — 비교 모드면 선택 토글, 아니면 상세 화면 진입
  void _onCardTap(RecommendationDto rec) {
    if (_isCompareMode) {
      setState(() {
        if (_selectedForCompare.contains(rec.restaurantId)) {
          _selectedForCompare.remove(rec.restaurantId);
        } else {
          // 3개까지만 선택 허용
          if (_selectedForCompare.length >= 3) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('최대 3개까지 비교할 수 있어요.')),
            );
            return;
          }
          _selectedForCompare.add(rec.restaurantId);
        }
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RestaurantDetailScreen(
            restaurantId: rec.restaurantId,
            initialName: rec.name,
          ),
        ),
      );
    }
  }

  // 비교 화면으로 이동
  void _openComparison() {
    final recs = _recommendations ?? const <RecommendationDto>[];
    final selected = recs
        .where((r) => _selectedForCompare.contains(r.restaurantId))
        .toList();

    if (selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비교하려면 2개 이상 선택해야 해요.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RestaurantComparisonScreen(recommendations: selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(
        showBack: true,
        title: 'AI 추천',
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      // 비교 모드면 비교 CTA, 아니면 "투표 시작" CTA 노출 (호스트만 의미 있음)
      bottomNavigationBar: _isCompareMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppPrimaryButton(
                  label: '${_selectedForCompare.length}개 비교하기',
                  onPressed:
                      _selectedForCompare.length >= 2 ? _openComparison : null,
                ),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppPrimaryButton(
                  label: _isStartingVote ? '투표 시작 중...' : '투표 시작하기',
                  onPressed: _isStartingVote ? null : _startVoting,
                ),
              ),
            ),
    );
  }

  // 투표 상태 전이 진행 중인지 — 중복 클릭 방지
  bool _isStartingVote = false;

  // ── 투표 시작 — PATCH /sessions/:id/status { status: 'VOTING' } ──
  // 백엔드가 호스트 권한을 검증. 호스트가 아니면 403/400 응답이 오므로 UI 에서
  // 별도 권한 가드는 두지 않음 (호스트 정보를 캐시하지 않는 정책).
  Future<void> _startVoting() async {
    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 정보가 없습니다.')),
      );
      return;
    }

    setState(() => _isStartingVote = true);

    final ok = await const SessionsApiService().updateSessionStatus(
      accessToken: token,
      sessionId: widget.sessionId,
      status: 'VOTING',
    );

    if (!mounted) return;
    setState(() => _isStartingVote = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('투표가 시작됐어요! 멤버 모두에게 알림이 갈 거예요.'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      // 시연 흐름: 로비로 복귀 후 상태 갱신
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('투표 시작에 실패했어요. 호스트만 시작할 수 있어요.'),
        ),
      );
    }
  }

  Widget _buildBody() {
    // 로딩 상태
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 에러 상태 (현재는 토큰 없음 케이스만)
    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: AppTextStyles.bodyMedium),
      );
    }

    final recs = _recommendations ?? const <RecommendationDto>[];

    // 빈 결과
    if (recs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.restaurant_outlined,
              size: 48,
              color: AppColors.iconInactive,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '추천할 식당이 없어요',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '식당 데이터가 등록되면 다시 시도해 주세요',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPrimaryButton(
              label: '다시 불러오기',
              onPressed: () {
                setState(() => _isLoading = true);
                _loadRecommendations();
              },
            ),
          ],
        ),
      );
    }

    // 정상 리스트
    return Column(
      children: [
        // ── 세션 이름 헤더 ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.sessionName,
                      style: AppTextStyles.heading3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '참여 멤버 조건 기반 추천 ${recs.length}개',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 지도 보기 버튼 (CU-15 지도/리스트 토글)
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: '지도 보기',
                onPressed: () {
                  final recs = _recommendations ?? const <RecommendationDto>[];
                  if (recs.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('추천 식당이 없어 지도로 볼 수 없어요.')),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecommendationMapScreen(
                        recommendations: recs,
                        sessionName: widget.sessionName,
                      ),
                    ),
                  );
                },
              ),
              // 비교 모드 토글 버튼
              IconButton(
                icon: Icon(
                  _isCompareMode
                      ? Icons.compare_arrows_rounded
                      : Icons.compare_rounded,
                  color: _isCompareMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: _isCompareMode ? '비교 모드 끄기' : '비교 모드 켜기',
                onPressed: _toggleCompareMode,
              ),
              // 새로고침 버튼
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: '새로고침',
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadRecommendations();
                },
              ),
            ],
          ),
        ),

        // ── 추천 카드 목록 ───────────────────────────────
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.xl,
            ),
            physics: const BouncingScrollPhysics(),
            itemCount: recs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => _buildRecommendationCard(recs[i], i + 1),
          ),
        ),
      ],
    );
  }

  // ── 추천 카드 하나 ────────────────────────────────────
  // 순위(1, 2, 3...) / 이름 / 카테고리 / 가격대 / 점수 / 근거 태그
  Widget _buildRecommendationCard(RecommendationDto rec, int rank) {
    final primary = Theme.of(context).colorScheme.primary;

    // 가격대 레이블
    final priceLabel = rec.priceRange != null
        ? '${_formatWithComma(rec.priceRange!)}원대'
        : '가격 미정';

    // 비교 모드에서 선택된 카드는 테두리 강조
    final isSelected = _selectedForCompare.contains(rec.restaurantId);

    return AppCard(
      onTap: () => _onCardTap(rec),
      padding: const EdgeInsets.all(AppSpacing.md),
      // 비교 모드에서 선택되면 주황 테두리로 강조 (두께는 AppCard 기본)
      borderColor: isSelected ? primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 순위 배지 + 이름 + 점수 ───────────────────
          Row(
            children: [
              // 순위 원형 배지 (1~3등은 강조색, 그 이하는 회색)
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank <= 3 ? primary : AppColors.backgroundGrey,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: AppTextStyles.label.copyWith(
                    color: rank <= 3 ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // 식당 이름
              Expanded(
                child: Text(
                  rec.name,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 점수 배지 (숫자만 작게)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  '점수 ${rec.score}',
                  style: AppTextStyles.caption.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── 카테고리 + 가격대 ─────────────────────────
          Row(
            children: [
              if (rec.category != null) ...[
                Icon(
                  Icons.restaurant_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(rec.category!, style: AppTextStyles.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(
                Icons.payments_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(priceLabel, style: AppTextStyles.bodySmall),
            ],
          ),

          // ── 주소 ───────────────────────────────────────
          if (rec.address != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    rec.address!,
                    style: AppTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // ── 추천 근거 태그들 ──────────────────────────
          if (rec.reasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rec.reasons.map((reason) {
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
                    reason,
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
    );
  }

  // ── 정수 → "12,345" 형태 천단위 콤마 포맷 ────────────
  String _formatWithComma(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
