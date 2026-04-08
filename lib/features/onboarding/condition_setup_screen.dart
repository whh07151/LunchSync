import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../services/users_api_service.dart';
import '../../providers/user_provider.dart';
import '../splash/splash_screen.dart'; // markOnboardingDone() 사용

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-05 기본 조건 설정 화면 (온보딩 2단계)
//
// 와이어프레임 참고: CU-09 조건 설정 화면 (반경/예산/빠른 복귀 설정)
//
// 구성 요소:
//   - 상단: 온보딩 진행 단계 표시 (2/3)
//   - 제목: "기본 조건을 설정해주세요" + 안내 문구
//   - 반경 슬라이더: 500m ~ 3km (도보 이동 범위)
//   - 예산 칩 선택: 5,000원 / 8,000원 / 12,000원 / 15,000원 이상
//   - 식사 속도 칩 선택: 빠르게 / 보통 / 여유롭게
//   - 하단 "홈으로 이동" 버튼
//
// 동작 흐름:
//   이전 화면(기본 프로필, CU-03) → 이 화면
//   → 반경/예산/속도 조건 선택 (모두 기본값 있음 → 버튼 항상 활성)
//   → "홈으로 이동" 버튼 탭 → 홈 대시보드(CU-06)로 이동
//
// 저장 방식:
//   현재는 로컬 상태(setState)만 사용.
//   TODO: 상태 관리 라이브러리 결정 후 전역 상태 또는 DB에 저장
//
// 상태 관리 라이브러리 무관:
//   콜백(onComplete) 방식으로 구현되어 있어,
//   어떤 상태 관리를 선택하더라도 이 파일은 수정 불필요.
// ══════════════════════════════════════════════════════════

class ConditionSetupScreen extends ConsumerStatefulWidget {
  const ConditionSetupScreen({
    super.key,
    required this.onComplete,
    required this.profileName, // CU-03에서 입력한 이름
    required this.profileOrg,  // CU-03에서 입력한 소속
  });

  /// 온보딩 완료 후 홈으로 이동하는 콜백
  final VoidCallback onComplete;

  /// CU-03 ProfileSetupScreen에서 전달받은 프로필 데이터
  final String profileName;
  final String profileOrg;

  @override
  ConsumerState<ConditionSetupScreen> createState() =>
      _ConditionSetupScreenState();
}

class _ConditionSetupScreenState extends ConsumerState<ConditionSetupScreen> {
  // ── 반경 슬라이더 상태 ─────────────────────────────────
  // 단위: 미터(m). 500m~3000m 범위에서 선택.
  // 기본값: 1000m(1km) — 일반적인 도보 점심 거리
  // TODO: 수치 확정 시 수정 — 기본 반경 값 및 최소/최대 범위
  double _radiusMeters = 1000;

  // ── 예산 선택 상태 ─────────────────────────────────────
  // 선택지 중 하나를 고르는 방식 (단일 선택)
  // 기본값: '1만원 이하' — 일반적인 직장인 점심 예산
  // TODO: 수치 확정 시 수정 — 예산 단계 및 기본값
  String _selectedBudget = '1만원 이하';

  // 예산 선택지 목록
  static const List<String> _budgetOptions = [
    '5천원 이하',
    '8천원 이하',
    '1만원 이하',
    '1만5천원 이하',
    '제한 없음',
  ];

  // ── 식사 속도 선택 상태 ────────────────────────────────
  // 점심 시간 여유에 따라 선택 (단일 선택)
  // 기본값: '보통' — 30~40분 기준
  // TODO: 수치 확정 시 수정 — 속도 옵션 및 기본값
  // API 전송 값: 명세서 기준 영문 (FAST / NORMAL / SLOW)
  String _selectedSpeed = 'NORMAL';

  // 속도 API 값 목록 (서버로 전송되는 실제 값)
  static const List<String> _speedOptions = ['FAST', 'NORMAL', 'SLOW'];

  // API 값 → 화면 표시 한국어 레이블
  static const Map<String, String> _speedLabel = {
    'FAST': '빠르게',
    'NORMAL': '보통',
    'SLOW': '여유롭게',
  };

  // API 값 → 소요 시간 설명
  // TODO: 수치 확정 시 수정 — 실제 소요 시간 기준으로 수정
  static const Map<String, String> _speedDescription = {
    'FAST': '20분 내외',
    'NORMAL': '30~40분',
    'SLOW': '1시간 이상',
  };

  // ── API 서비스 ────────────────────────────────────────
  static const _usersApiService = UsersApiService();

  // ── 저장 중 여부 ──────────────────────────────────────
  bool _isSaving = false;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-05');
  }

  // ── 슬라이더 미터값 → API 반경 문자열 변환 ─────────────
  // 예: 1000 → '1km', 500 → '500m'
  String _radiusToString(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return '${km == km.truncateToDouble() ? km.toInt() : km}km';
    }
    return '${meters.toInt()}m';
  }

  // ── 예산 문자열 → 정수 변환 ───────────────────────────
  // DB budget 컬럼은 INTEGER
  int? _budgetToInt(String budget) {
    switch (budget) {
      case '5천원 이하': return 5000;
      case '8천원 이하': return 8000;
      case '1만원 이하': return 10000;
      case '1만5천원 이하': return 15000;
      case '제한 없음': return null;
      default: return null;
    }
  }

  // ── 온보딩 완료: API 호출 → 온보딩 완료 플래그 저장 → 홈으로 이동 ───
  // 처리 순서:
  //   1. PATCH /users/me — CU-03(이름/소속) + CU-05(반경/예산/속도) 한 번에 저장
  //   2. markOnboardingDone() — SharedPreferences에 'onboarding_done' = true 저장
  //      → 앱 재실행 시 스플래시 건너뛰고 로그인 화면으로 바로 진입
  //   3. onComplete() — 홈 화면으로 이동
  Future<void> _handleComplete() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final accessToken = ref.read(userProvider).accessToken;

    if (accessToken != null) {
      await _usersApiService.updateMe(
        accessToken: accessToken,
        name: widget.profileName,
        org: widget.profileOrg,
        radius: _radiusToString(_radiusMeters),
        budget: _budgetToInt(_selectedBudget),
        speed: _selectedSpeed,
      );
    }

    // 온보딩 완료 기록: 다음 실행부터 스플래시 건너뜀
    await markOnboardingDone();

    if (!mounted) return;
    setState(() => _isSaving = false);
    widget.onComplete();
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // ── 앱바: 뒤로가기 버튼 ──────────────────────────────
      // 이전 화면(프로필 설정)으로 돌아갈 수 있음
      appBar: AppCustomBar(showBack: true),

      body: SafeArea(
        child: Column(
          children: [

            // ── 스크롤 가능한 콘텐츠 영역 ──────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    const SizedBox(height: AppSpacing.lg),

                    // ── 온보딩 진행 단계 표시 ───────────────
                    _buildStepIndicator(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── 화면 제목 + 안내 문구 ───────────────
                    _buildHeader(),

                    const SizedBox(height: AppSpacing.xl),

                    // ── 반경 슬라이더 섹션 ──────────────────
                    _buildRadiusSection(),

                    // TODO: 수치 확정 시 수정 — 섹션 사이 간격 (현재 28px)
                    const SizedBox(height: AppSpacing.lg + 4),

                    // ── 구분선 ───────────────────────────────
                    const Divider(color: AppColors.divider, height: 1),

                    const SizedBox(height: AppSpacing.lg + 4),

                    // ── 예산 선택 섹션 ──────────────────────
                    _buildBudgetSection(),

                    const SizedBox(height: AppSpacing.lg + 4),

                    // ── 구분선 ───────────────────────────────
                    const Divider(color: AppColors.divider, height: 1),

                    const SizedBox(height: AppSpacing.lg + 4),

                    // ── 식사 속도 선택 섹션 ─────────────────
                    _buildSpeedSection(),

                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),

            // ── 하단 고정 버튼 영역 ────────────────────────
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  // ── 온보딩 진행 단계 표시 위젯 ───────────────────────────
  // 2단계 활성화 (CU-03이 1단계, 이 화면이 2단계)
  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(
        3,
        (index) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                // 0번(1단계): 완료 → 진한 primary
                // 1번(2단계=현재): 활성 → primary
                // 2번(3단계): 미완료 → 연한 회색
                color: index <= 1
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.border,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 화면 제목 + 안내 문구 위젯 ────────────────────────────
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2단계',
          style: AppTextStyles.label.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '기본 조건을\n설정해주세요',
          style: AppTextStyles.heading1,
        ),
        const SizedBox(height: 10),
        Text(
          // TODO: 수정 필요 — 실제 안내 문구로 교체
          '나중에 설정 메뉴에서 언제든지 바꿀 수 있어요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 반경 슬라이더 섹션 위젯 ────────────────────────────────
  // 슬라이더를 드래그해서 반경을 연속적으로 선택
  Widget _buildRadiusSection() {
    final primary = Theme.of(context).colorScheme.primary;

    // 현재 선택된 반경을 사람이 읽기 쉬운 문자열로 변환
    // 1000m 이상이면 km 단위로 표시, 미만이면 m 단위로 표시
    final String radiusLabel = _radiusMeters >= 1000
        ? '${(_radiusMeters / 1000).toStringAsFixed(1)}km'
        : '${_radiusMeters.toInt()}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── 섹션 제목 + 현재 선택값 ────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '도보 반경',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            // 현재 선택된 반경을 주황색 텍스트로 강조 표시
            Text(
              radiusLabel,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),

        // 섹션 안내 문구
        Text(
          // TODO: 수정 필요 — 실제 안내 문구로 교체
          '도보로 이동 가능한 식당 추천 범위예요',
          style: AppTextStyles.bodySmall,
        ),

        // TODO: 수치 확정 시 수정 — 슬라이더 상하 여백
        const SizedBox(height: 12),

        // ── 슬라이더 ────────────────────────────────────────
        SliderTheme(
          // SliderTheme: 슬라이더의 시각적 스타일을 커스터마이징
          data: SliderThemeData(
            // 활성 구간(왼쪽) 색상: primary 색
            activeTrackColor: primary,
            // 비활성 구간(오른쪽) 색상: 연한 회색
            inactiveTrackColor: AppColors.border,
            // 드래그 원(thumb) 색상: primary 색
            thumbColor: primary,
            // 원 외곽선 색상 (없음)
            overlayColor: primary.withAlpha(30),
            // 트랙 두께
            trackHeight: 4,
          ),
          child: Slider(
            value: _radiusMeters,
            // TODO: 수치 확정 시 수정 — 슬라이더 최소/최대값 및 단계
            min: 300,    // 최소 300m
            max: 3000,   // 최대 3km
            divisions: 9, // 300m 간격으로 9칸 (300,600,...,2700,3000)
            onChanged: (value) {
              setState(() => _radiusMeters = value);
            },
          ),
        ),

        // ── 슬라이더 양 끝 레이블 ───────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('300m', style: AppTextStyles.caption),
              Text('3km', style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }

  // ── 예산 선택 섹션 위젯 ────────────────────────────────────
  Widget _buildBudgetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 섹션 제목
        Text(
          '1인 예산',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          // TODO: 수정 필요 — 실제 안내 문구로 교체
          '점심 한 끼에 쓸 수 있는 금액을 선택해주세요',
          style: AppTextStyles.bodySmall,
        ),

        const SizedBox(height: 12),

        // ── 예산 칩 목록 ──────────────────────────────────
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _budgetOptions.map((budget) {
            return AppChip(
              label: budget,
              isSelected: _selectedBudget == budget,
              onTap: () => setState(() => _selectedBudget = budget),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 식사 속도 선택 섹션 위젯 ──────────────────────────────
  Widget _buildSpeedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 섹션 제목
        Text(
          '식사 속도',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          // TODO: 수정 필요 — 실제 안내 문구로 교체
          '보통 점심 시간에 얼마나 여유가 있나요?',
          style: AppTextStyles.bodySmall,
        ),

        const SizedBox(height: 12),

        // ── 속도 선택 카드 목록 ────────────────────────────
        // 칩 대신 카드 형태로 표시: 설명 문구가 들어가야 하므로
        Row(
          children: _speedOptions.map((speed) {
            final isSelected = _selectedSpeed == speed;
            final primary = Theme.of(context).colorScheme.primary;

            return Expanded(
              child: Padding(
                // 카드 사이 좌우 간격
                padding: EdgeInsets.only(
                  right: speed != _speedOptions.last ? 8 : 0,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedSpeed = speed),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      // 선택됐으면 연한 primary 배경, 아니면 흰색
                      color: isSelected
                          ? primary.withAlpha(20)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        // 선택됐으면 primary 테두리, 아니면 회색 테두리
                        color: isSelected ? primary : AppColors.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // 속도 표시 레이블 (빠르게 / 보통 / 여유롭게)
                        // 내부 값은 FAST/NORMAL/SLOW, 화면엔 한국어로 표시
                        Text(
                          _speedLabel[speed] ?? speed,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? primary
                                : AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        // 소요 시간 설명 (20분 내외 / 30~40분 / 1시간 이상)
                        Text(
                          _speedDescription[speed] ?? '',
                          style: AppTextStyles.caption.copyWith(
                            color: isSelected
                                ? primary.withAlpha(180)
                                : AppColors.textHint,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 하단 고정 버튼 영역 위젯 ──────────────────────────────
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        12,
        AppSpacing.screenHorizontal,
        32,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: AppPrimaryButton(
        // 모든 조건에 기본값이 있으므로 항상 활성 상태
        label: _isSaving ? '저장 중...' : '홈으로 이동',
        isEnabled: !_isSaving,
        onPressed: _isSaving ? null : _handleComplete,
      ),
    );
  }
}