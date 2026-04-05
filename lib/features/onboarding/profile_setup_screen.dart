import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-03 기본 프로필 설정 화면
//
// 와이어프레임 기준 구성 요소:
//   - 상단: 온보딩 진행 단계 표시 (1/3)
//   - 제목: "기본 프로필 설정" + 안내 문구
//   - 프로필 사진 선택 영역 (원형, 카메라 아이콘)
//   - 이름 입력 필드
//   - 소속 입력 필드
//   - 기본 반경 칩 선택 (300m / 500m / 1km / 2km)
//   - 하단 "다음" 버튼
//
// 동작 흐름:
//   이전 화면(로그인 또는 스플래시) → 이 화면
//   → 이름/소속 입력 + 반경 선택 완료
//   → "다음" 버튼 탭 → 다음 온보딩 화면(CU-05)으로 이동
//
// 유효성 검사:
//   이름과 소속이 모두 입력되어야 "다음" 버튼이 활성화됩니다.
//   반경은 기본값(500m)이 선택되어 있어 항상 유효합니다.
//
// 상태 관리 라이브러리 무관:
//   콜백(onNext) 방식으로 구현되어 있어,
//   어떤 상태 관리를 선택하더라도 이 파일은 수정 불필요.
// ══════════════════════════════════════════════════════════

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.onNext, // "다음" 버튼 탭 시 실행: 다음 온보딩 화면으로 이동
  });

  /// "다음" 버튼을 눌렀을 때 실행되는 함수
  /// → 다음 온보딩 화면(기본 조건 설정, CU-05)으로 이동
  final VoidCallback onNext;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // ── 입력값 컨트롤러 ────────────────────────────────────
  // TextEditingController: 텍스트 필드의 내용을 읽거나 지울 때 사용
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _orgController = TextEditingController();

  // ── 반경 선택 상태 ─────────────────────────────────────
  // 기본값 500m: 일반적인 도보 점심 거리에 해당
  String _selectedRadius = '500m';

  // 반경 선택지 목록: 칩으로 표시될 옵션들
  // TODO: 수치 확정 시 수정 — 실제 서비스에서 제공할 반경 단위로 변경
  static const List<String> _radiusOptions = ['300m', '500m', '1km', '2km'];

  // ── 유효성 검사 ─────────────────────────────────────────
  // 이름과 소속이 모두 입력됐을 때만 true → "다음" 버튼 활성화
  bool get _canProceed =>
      _nameController.text.trim().isNotEmpty &&
      _orgController.text.trim().isNotEmpty;

  // ── 생명주기: 화면이 처음 만들어질 때 ──────────────────
  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-03');
    // 텍스트가 바뀔 때마다 _canProceed를 다시 계산해서 버튼 활성화 상태 갱신
    _nameController.addListener(() => setState(() {}));
    _orgController.addListener(() => setState(() {}));
  }

  // ── 생명주기: 화면이 사라질 때 ─────────────────────────
  @override
  void dispose() {
    // 컨트롤러는 화면이 사라질 때 반드시 해제해야 메모리 누수가 없음
    _nameController.dispose();
    _orgController.dispose();
    super.dispose();
  }

  // ── UI 구성 ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // ── 앱바: 뒤로가기 버튼 ──────────────────────────────
      // 온보딩 첫 단계이므로 뒤로가기 허용
      // (로그인 화면이 완성되면 뒤로가면 로그인으로 돌아감)
      appBar: AppCustomBar(showBack: true),

      body: SafeArea(
        // SafeArea: 노치, 상태바, 하단 홈바 영역을 피해서 배치
        child: Column(
          children: [

            // ── 스크롤 가능한 콘텐츠 영역 ──────────────────
            // Expanded: 남은 공간을 모두 차지
            // SingleChildScrollView: 콘텐츠가 길어지면 스크롤 가능
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  // TODO: 수치 확정 시 수정 — 화면 좌우 여백 (현재 20px)
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // TODO: 수치 확정 시 수정 — 앱바 아래 상단 여백 (현재 24px)
                    const SizedBox(height: AppSpacing.lg),

                    // ── 온보딩 진행 단계 표시 ───────────────
                    _buildStepIndicator(),

                    // TODO: 수치 확정 시 수정 — 단계 표시와 제목 사이 간격 (현재 24px)
                    const SizedBox(height: AppSpacing.lg),

                    // ── 화면 제목 + 안내 문구 ───────────────
                    _buildHeader(),

                    // TODO: 수치 확정 시 수정 — 제목과 프로필 사진 사이 간격 (현재 32px)
                    const SizedBox(height: AppSpacing.xl),

                    // ── 프로필 사진 선택 영역 ───────────────
                    _buildProfilePhoto(context),

                    // TODO: 수치 확정 시 수정 — 프로필 사진과 입력 필드 사이 간격 (현재 32px)
                    const SizedBox(height: AppSpacing.xl),

                    // ── 이름 입력 필드 ──────────────────────
                    AppTextField(
                      controller: _nameController,
                      label: '이름',
                      hint: '실명을 입력해주세요',
                      // TextInputAction.next: 키보드의 "다음" 버튼 → 다음 필드로 이동
                      textInputAction: TextInputAction.next,
                      // maxLength: 이름은 최대 20자로 제한
                      // TODO: 수치 확정 시 수정 — 이름 최대 글자 수
                      maxLength: 20,
                    ),

                    // TODO: 수치 확정 시 수정 — 필드 사이 간격 (현재 20px)
                    const SizedBox(height: AppSpacing.md + 4),

                    // ── 소속 입력 필드 ──────────────────────
                    AppTextField(
                      controller: _orgController,
                      label: '소속',
                      hint: '회사 또는 팀 이름을 입력해주세요',
                      // TextInputAction.done: 키보드의 "완료" 버튼 → 키보드 닫힘
                      textInputAction: TextInputAction.done,
                      // TODO: 수치 확정 시 수정 — 소속 최대 글자 수
                      maxLength: 30,
                    ),

                    // TODO: 수치 확정 시 수정 — 소속 필드와 반경 섹션 사이 간격 (현재 28px)
                    const SizedBox(height: AppSpacing.lg + 4),

                    // ── 기본 반경 선택 섹션 ─────────────────
                    _buildRadiusSection(),

                    // 스크롤 영역 하단 여백
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),

            // ── 하단 버튼 영역 ──────────────────────────────
            // 스크롤과 무관하게 항상 화면 하단에 고정됨
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  // ── 온보딩 진행 단계 표시 위젯 ───────────────────────────
  // 사용자가 전체 온보딩 중 어느 단계인지 시각적으로 알 수 있게 함
  // CU-03(프로필) → CU-05(조건 설정) → 완료 의 3단계 기준
  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(
        // TODO: 수치 확정 시 수정 — 온보딩 총 단계 수 (현재 3단계 기준)
        3,
        (index) => Expanded(
          child: Padding(
            // 막대들 사이 간격
            padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
            child: AnimatedContainer(
              // AnimatedContainer: 상태가 바뀔 때 부드럽게 색상이 전환됨
              duration: const Duration(milliseconds: 300),
              height: 4, // 진행 막대 두께
              decoration: BoxDecoration(
                // 현재 단계(0번 = 1단계)는 primary 색, 나머지는 연한 회색
                color: index == 0
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
        // 화면 단계 레이블
        // TODO: 수치 확정 시 수정 — 단계 레이블 텍스트 (현재 "1단계")
        Text(
          '1단계',
          style: AppTextStyles.label.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),

        // TODO: 수치 확정 시 수정 — 레이블과 제목 사이 간격 (현재 6px)
        const SizedBox(height: 6),

        // 화면 제목
        // TODO: 수정 필요 — 실제 제목 문구 확정 시 교체
        Text(
          '기본 프로필을\n설정해주세요',
          style: AppTextStyles.heading1,
        ),

        // TODO: 수치 확정 시 수정 — 제목과 안내 문구 사이 간격 (현재 10px)
        const SizedBox(height: 10),

        // 안내 문구
        // TODO: 수정 필요 — 실제 안내 문구로 교체
        Text(
          '점심 세션에서 팀원들에게 표시될 이름과\n소속을 입력해주세요',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // ── 프로필 사진 선택 영역 위젯 ────────────────────────────
  // 원형 아바타에 카메라 아이콘이 있는 형태
  // 탭하면 갤러리/카메라 선택 시트가 열릴 예정 (TODO: 추후 구현)
  Widget _buildProfilePhoto(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: GestureDetector(
        // TODO: 구현 필요 — 탭 시 갤러리/카메라 선택 바텀시트 표시
        // 현재는 탭해도 아무 동작 없음 (데모용)
        onTap: () {},
        child: Stack(
          // clipBehavior.none: Stack 범위를 벗어나는 자식 위젯도 표시됨
          // (+ 배지가 원 밖으로 약간 나오게 하기 위해 필요)
          clipBehavior: Clip.none,
          children: [

            // ── 프로필 사진 원형 영역 ──────────────────────
            Container(
              // TODO: 수치 확정 시 수정 — 프로필 원 크기 (현재 88x88px)
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                // TODO: 수정 필요 — 사진 선택 후 선택한 이미지로 배경 교체
                // 현재: 아주 연한 주황 배경 (빈 상태를 나타냄)
                color: _AppColorsX.primarySurface(context),
                shape: BoxShape.circle,
                border: Border.all(
                  color: primary.withAlpha(60), // 주황색 반투명 테두리
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  // TODO: 수정 필요 — 사진 선택 후 선택한 이미지 표시
                  // 현재: 임시 사람 아이콘
                  Icons.person_rounded,
                  size: 44,
                  color: primary.withAlpha(120),
                ),
              ),
            ),

            // ── 카메라 아이콘 배지 (우측 하단) ──────────────
            // Positioned: Stack 안에서 위치를 직접 지정하는 위젯
            Positioned(
              // TODO: 수치 확정 시 수정 — 배지 위치 (현재 우측 하단 -2px)
              right: -2,
              bottom: -2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primary, // 주황색 배경
                  shape: BoxShape.circle,
                  // 흰색 테두리: 배지가 사진 원과 겹칠 때 구분되게 함
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 기본 반경 선택 섹션 위젯 ──────────────────────────────
  // 칩(Chip) 형태로 반경 옵션을 나열하고, 하나를 선택할 수 있음
  Widget _buildRadiusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 섹션 제목
        Text(
          '기본 반경',
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),

        // TODO: 수치 확정 시 수정 — 섹션 제목과 안내 문구 사이 간격 (현재 4px)
        const SizedBox(height: AppSpacing.xs),

        // 섹션 안내 문구
        // TODO: 수정 필요 — 실제 안내 문구로 교체
        Text(
          '점심 식당을 추천할 때 기준이 되는 도보 거리예요',
          style: AppTextStyles.bodySmall,
        ),

        // TODO: 수치 확정 시 수정 — 안내 문구와 칩 사이 간격 (현재 12px)
        const SizedBox(height: AppSpacing.sm + 4),

        // ── 반경 칩 목록 ──────────────────────────────────
        // Wrap: 칩이 넘치면 다음 줄로 자동 줄바꿈됨
        Wrap(
          spacing: AppSpacing.sm,   // 칩 사이 가로 간격
          runSpacing: AppSpacing.sm, // 줄 사이 세로 간격
          children: _radiusOptions.map((radius) {
            return AppChip(
              label: radius,
              // 현재 선택된 반경과 같으면 활성 상태로 표시
              isSelected: _selectedRadius == radius,
              onTap: () {
                // 탭하면 해당 반경으로 선택 상태 변경
                setState(() => _selectedRadius = radius);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 하단 고정 버튼 영역 위젯 ──────────────────────────────
  // 스크롤 위치와 무관하게 항상 화면 맨 아래에 고정됨
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        // TODO: 수치 확정 시 수정 — 버튼 영역 여백 (현재 좌우 20px, 하단 32px, 상단 12px)
        AppSpacing.screenHorizontal,
        12,
        AppSpacing.screenHorizontal,
        32,
      ),
      // 버튼 영역 위에 얇은 구분선 표시
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: AppPrimaryButton(
        label: '다음',
        // _canProceed가 true(이름+소속 입력됨)일 때만 버튼 활성화
        isEnabled: _canProceed,
        onPressed: _canProceed ? widget.onNext : null,
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════
// AppColors 확장: primarySurface를 컨텍스트에서 쓸 수 있도록 헬퍼 메서드 추가
//
// 왜 필요한가?
//   AppColors.primarySurface는 손님앱/점주앱 구분 없이 고정색(주황 연한 배경)임.
//   하지만 프로필 화면은 테마(손님/점주)에 따라 달라져야 하므로,
//   Theme.of(context).colorScheme.primary 기반으로 동적으로 계산함.
// ══════════════════════════════════════════════════════════
extension _AppColorsX on AppColors {
  /// 현재 테마의 primary 색을 기반으로 한 연한 배경색
  /// 손님앱: 연한 주황, 점주앱: 연한 청록
  static Color primarySurface(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // withAlpha(25): 약 10% 불투명도 → 아주 연한 배경
    return primary.withAlpha(25);
  }
}