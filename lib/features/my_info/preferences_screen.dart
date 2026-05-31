import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/users_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-04 취향/알레르기/비선호 카테고리 설정 화면
//
// 진입 경로:
//   내정보 탭(MyInfoScreen) > 앱 설정 > "취향 설정" 행 (Icons.tune)
//
// 데이터 흐름:
//   1) 진입 시 userProvider.tasteTags / allergens / dislikedCategories
//      를 그대로 초기 선택 상태로 사용 (이미 GET /users/me 로 로드됨).
//   2) FilterChip 다중 선택 — 토글 가능.
//   3) "저장" → PATCH /api/users/me/preferences
//        성공: userProvider 캐시 갱신 + SnackBar "저장됐어요"
//        실패: SnackBar 오류 안내, 변경 사항 유지
//
// 추천 엔진 연동:
//   - tasteTags: 추천 점수 +α (선호 맛 보너스)
//   - allergens: 해당 식재료가 든 메뉴 보유 식당은 후보군에서 제외
//   - dislikedCategories: 해당 카테고리 점수 감점
//   세 라벨은 백엔드/추천 엔진과 1:1 일치해야 함 — 변경 시 양쪽 동시 수정 필수.
//
// 디자인 토큰만 사용 — 새 색상/그라디언트 추가하지 않음.
// ══════════════════════════════════════════════════════════

class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  // ── API 서비스 ────────────────────────────────────────────
  // const 생성자라 매 빌드 신규 인스턴스 생성 비용 0.
  static const _usersApiService = UsersApiService();

  // ── 화면 상태 ────────────────────────────────────────────
  // _isSaving: PATCH 진행 중인지 여부 — 저장 버튼 비활성화/스피너 표시.
  bool _isSaving = false;

  // ── 현재 선택 상태 (Set 으로 중복 자동 차단) ──────────────
  // initState 에서 userProvider 의 현재값으로 채워짐.
  final Set<String> _tasteTags = <String>{};
  final Set<String> _allergens = <String>{};
  final Set<String> _dislikedCategories = <String>{};

  // ── 선택지 목록 (백엔드/추천 엔진과 1:1 일치) ────────────
  // 라벨 변경 시 backend/src/recommend/* 도 동시 수정 필요.

  // 좋아하는 맛 — 추천 점수 +α 보너스.
  static const List<String> _tasteOptions = [
    '매콤',
    '담백',
    '짠',
    '단',
    '신',
    '쓴',
  ];

  // 알레르기 식재료 — 해당 메뉴 보유 식당은 후보군 제외.
  static const List<String> _allergenOptions = [
    '견과',
    '유제품',
    '계란',
    '갑각류',
    '콩',
    '밀',
    '돼지',
    '소',
  ];

  // 비선호 카테고리 — 추천 점수 감점.
  static const List<String> _categoryOptions = [
    '한식',
    '중식',
    '일식',
    '양식',
    '분식',
    '패스트푸드',
    '카페',
    '디저트',
  ];

  // ── 생명주기: 초기화 ─────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // userProvider 의 현재 값으로 초기 선택 상태 채움.
    // 빈 배열이면 모두 미선택 → 사용자가 처음 진입하는 케이스.
    final user = ref.read(userProvider);
    _tasteTags.addAll(user.tasteTags);
    _allergens.addAll(user.allergens);
    _dislikedCategories.addAll(user.dislikedCategories);
  }

  // ── 칩 토글 헬퍼 ──────────────────────────────────────────
  // 동일 항목이 있으면 제거, 없으면 추가 → 다중 선택 토글.
  void _toggle(Set<String> bucket, String value) {
    setState(() {
      if (!bucket.add(value)) {
        bucket.remove(value);
      }
    });
  }

  // ── 저장: PATCH /api/users/me/preferences ─────────────────
  // 성공: userProvider 캐시 갱신 + SnackBar
  // 실패: SnackBar 오류 안내 (선택 상태는 유지)
  Future<void> _save() async {
    if (_isSaving) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null || token.isEmpty) {
      // 로그인 가드 — 정상 흐름에서는 진입 자체가 차단되지만 방어적으로 처리.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인 후 다시 시도해 주세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Set → List 로 직렬화 (JSON 배열 매핑).
    final tasteTags = _tasteTags.toList();
    final allergens = _allergens.toList();
    final dislikedCategories = _dislikedCategories.toList();

    final result = await _usersApiService.updatePreferences(
      accessToken: token,
      tasteTags: tasteTags,
      allergens: allergens,
      dislikedCategories: dislikedCategories,
    );

    if (!mounted) return;

    if (result == null) {
      // 저장 실패 — 선택 상태는 유지하고 안내만 표시.
      setState(() => _isSaving = false);
      debugPrint('[PreferencesScreen] 저장 실패 (네트워크 또는 4xx/5xx)');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장에 실패했어요. 잠시 후 다시 시도해 주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 저장 성공 — Riverpod 캐시 즉시 갱신 → 추천 화면이 새 가중치 적용.
    ref.read(userProvider.notifier).setPreferences(
          tasteTags: result['tasteTags'] ?? const [],
          allergens: result['allergens'] ?? const [],
          dislikedCategories: result['dislikedCategories'] ?? const [],
        );

    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('취향 설정이 저장됐어요'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── UI 구성 ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,

      // ── 앱바 ─────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '취향 설정',
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: false,
        // 저장 중: 우상단 스피너로 진행 상태 가시화.
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(
                '저장',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            // ── 안내 헤더 ────────────────────────────────
            _buildIntroHeader(),

            const SizedBox(height: AppSpacing.md),

            // ── 좋아하는 맛 ──────────────────────────────
            _buildSection(
              title: '좋아하는 맛',
              hint: '추천 점수에 +α 가중치를 줘요',
              options: _tasteOptions,
              selected: _tasteTags,
              onToggle: (v) => _toggle(_tasteTags, v),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── 알레르기 ────────────────────────────────
            _buildSection(
              title: '알레르기',
              hint: '선택한 재료가 든 메뉴가 있는 식당은 추천에서 제외해요',
              options: _allergenOptions,
              selected: _allergens,
              onToggle: (v) => _toggle(_allergens, v),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── 비선호 카테고리 ─────────────────────────
            _buildSection(
              title: '비선호 음식',
              hint: '선택한 카테고리는 추천 우선순위를 낮춰요',
              options: _categoryOptions,
              selected: _dislikedCategories,
              onToggle: (v) => _toggle(_dislikedCategories, v),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  // ── 인트로 헤더 ───────────────────────────────────────────
  // "왜 이걸 묻나" 의도를 한 줄로 설명. 와이어 가이드에 따라 톤 따뜻하게.
  Widget _buildIntroHeader() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.tune,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 취향을 알려주세요',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '추천 식당이 더 똑똑해져요. 언제든 다시 바꿀 수 있어요.',
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

  // ── 섹션 위젯 ─────────────────────────────────────────────
  // 타이틀 + 안내 문구 + FilterChip 다중 선택 묶음.
  Widget _buildSection({
    required String title,
    required String hint,
    required List<String> options,
    required Set<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 타이틀
          Text(
            title,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          // 섹션 안내 (왜 이걸 묻는지)
          Text(
            hint,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // FilterChip 다중 선택 — 토글식.
          // (AppChip 은 단일 선택 톤이라 명시적 체크 인디케이터가 있는
          //  FilterChip 을 사용 — 알레르기/비선호처럼 신중한 선택이 필요한 곳에 적합)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: options.map((option) {
              final isSelected = selected.contains(option);
              return FilterChip(
                label: Text(option),
                selected: isSelected,
                onSelected: _isSaving ? null : (_) => onToggle(option),
                // 선택 시 primary 톤으로 강조, 미선택은 표준 회색.
                selectedColor: primary.withAlpha(40),
                checkmarkColor: primary,
                labelStyle: AppTextStyles.label.copyWith(
                  color:
                      isSelected ? primary : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(
                  color: isSelected ? primary : AppColors.border,
                ),
                backgroundColor: AppColors.backgroundGrey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.xl),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
