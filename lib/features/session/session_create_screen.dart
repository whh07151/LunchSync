import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/session_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/sessions_api_service.dart';
import '../../services/invitations_api_service.dart';
import '../../services/geolocation_service.dart';
import 'session_lobby_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: CU-09 점심 세션 생성 조건 설정 화면
//
// 진입 경로:
//   CU-08 멤버 선택(member_select_screen.dart)
//     → "조건 설정하기" 버튼 → 이 화면
//
// 반드시 넣을 UI (분해표 기준):
//   인원, 시간, 반경, 예산, 복귀시간, 메모
//
// 버튼·액션:
//   세션 만들기 — POST /sessions + POST /invitations → 로비 진입
//   조건 초기화 — 반경/예산/복귀시간을 기본값으로 리셋
//
// 완료 기준 (DoD):
//   세션 생성 후 SessionLobbyScreen(호스트 모드)으로 이동
//
// 단계 표시바:
//   1단계 인원(완료) → 2단계 조건(현재) → 3단계 AI추천
//
// 기본값:
//   반경 500m / 예산 15,000원 / 복귀시간 30분
// ══════════════════════════════════════════════════════════

// ── 기본값 상수 ──────────────────────────────────────────
// 매직 넘버는 lib/core/constants/app_constants.dart 의 SessionDefaults 로 이전.
// 아래는 파일 내부 가독성용 별칭 — 의미·의도는 SessionDefaults 주석 참조.
const _kDefaultRadius        = SessionDefaults.radiusMeters;        // 500m
const _kDefaultBudget        = SessionDefaults.budgetPerPersonWon;  // 15,000원
const _kDefaultReturnMinutes = SessionDefaults.returnMinutes;       // 30분

/// 호스트 GPS 조회 안전망 타임아웃.
///
/// 왜 8초?
///   - 카카오맵/플레이스 API 호출 전 단계라 너무 짧으면 정상 권한 응답까지 끊김.
///   - 너무 길면 권한 거부/스트림 이슈 시 사용자가 "세션 생성 중..." 로딩에 갇힘.
///   - GeolocationService 내부에도 동일한 timeLimit 을 넘겨 외부/내부가 일치하게 함
///     (이전: 외부 8s vs 내부 10s 로 내부 타임아웃이 죽은 코드였음).
const _kGpsLookupTimeout = Duration(seconds: 8);

class SessionCreateScreen extends ConsumerStatefulWidget {
  const SessionCreateScreen({super.key});

  @override
  ConsumerState<SessionCreateScreen> createState() =>
      _SessionCreateScreenState();
}

class _SessionCreateScreenState extends ConsumerState<SessionCreateScreen> {

  // ── 텍스트 컨트롤러 ───────────────────────────────────
  // 각 입력 필드의 텍스트 값을 읽고 초기화하기 위해 사용
  final _nameController         = TextEditingController(text: '점심 세션');
  final _radiusController       = TextEditingController(text: '$_kDefaultRadius');
  final _budgetController       = TextEditingController(text: '$_kDefaultBudget');
  final _returnMinutesController = TextEditingController(text: '$_kDefaultReturnMinutes');
  final _memoController         = TextEditingController();

  // ── 선택된 시간 ───────────────────────────────────────
  // null이면 "오늘 중"으로 표시 (scheduledAt 미설정)
  TimeOfDay? _selectedTime;

  // ── 생성 진행 상태 ────────────────────────────────────
  bool _isLoading = false;

  static const _sessionsApi    = SessionsApiService();
  static const _invitationsApi = InvitationsApiService();
  static const _geoService     = GeolocationService();

  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'CU-09');
  }

  @override
  void dispose() {
    // 컨트롤러 해제 — 메모리 누수 방지
    _nameController.dispose();
    _radiusController.dispose();
    _budgetController.dispose();
    _returnMinutesController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  // ── 조건 초기화 버튼 핸들러 ──────────────────────────
  // 반경/예산/복귀시간을 기본값으로 되돌림. 이름/시간/메모는 유지.
  void _resetConditions() {
    _radiusController.text        = '$_kDefaultRadius';
    _budgetController.text        = '$_kDefaultBudget';
    _returnMinutesController.text = '$_kDefaultReturnMinutes';
    setState(() => _selectedTime  = null);
  }

  // ── 시간 선택 다이얼로그 ──────────────────────────────
  // showTimePicker: Flutter 기본 제공 시간 선택 UI
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 12, minute: 0),
      helpText: '점심 시간 선택',
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  // ── 세션 만들기 버튼 핸들러 ───────────────────────────
  // 흐름:
  //   1. 입력값 검증
  //   2. POST /sessions → Session 객체 반환
  //   3. POST /invitations (초대코드 생성)
  //   4. SessionLobbyScreen(호스트 모드)으로 이동
  //
  // 라우팅 누락 버그 방지(2026-05-13 수정):
  //   - 전체 흐름을 try/catch/finally로 감싸 어떤 단계에서 예외가 나도
  //     반드시 _isLoading=false 로 복귀하고 사용자에게 안내한다.
  //   - GPS 조회에 명시적 안전망 타임아웃(8초)을 걸어 웹 권한 팝업에서
  //     무한 대기하는 케이스를 차단한다(GeolocationService 내부 10초와 별개).
  //   - 각 단계마다 debugPrint 로그를 남겨 어디서 멈췄는지 콘솔에서
  //     즉시 진단 가능하도록 한다.
  Future<void> _handleCreate() async {
    if (_isLoading) return;

    final token = ref.read(userProvider).accessToken;
    if (token == null) {
      _showError('로그인이 필요해요. 다시 로그인해주세요.');
      return;
    }

    // ── 1. 입력값 파싱 ─────────────────────────────────
    final name   = _nameController.text.trim();
    final radius = int.tryParse(_radiusController.text.trim());
    final budget = int.tryParse(_budgetController.text.trim());
    final returnMinutes = int.tryParse(_returnMinutesController.text.trim());
    final memo   = _memoController.text.trim();

    if (name.isEmpty) {
      _showError('세션 이름을 입력해주세요.');
      return;
    }

    // ── 2. scheduledAt 조립 ────────────────────────────
    // 시간만 선택하면 오늘 날짜 + 선택 시간으로 ISO8601 문자열 생성
    String? scheduledAt;
    if (_selectedTime != null) {
      final now = DateTime.now();
      final dt  = DateTime(
        now.year, now.month, now.day,
        _selectedTime!.hour, _selectedTime!.minute,
      );
      scheduledAt = dt.toIso8601String();
    }

    setState(() => _isLoading = true);
    debugPrint('[SessionCreate] SESSION_CREATE_STARTED');

    try {
      // ── 3. 호스트 GPS 조회 (외부 안전망 타임아웃 적용) ──
      // 호스트의 현재 GPS 좌표를 세션에 함께 저장 — 추천 엔진이 이 좌표를
      // 기준으로 반경 내 식당만 후보로 추린다. 위치 실패 시 null로 전달하면
      // 백엔드가 반경 필터를 생략하고 DB 전체 식당을 대상으로 폴백.
      //
      // 타임아웃 정책 (2026-05-13 정리):
      //   이전에는 GeolocationService 내부 10초 + 외부 8초로 중복이라 내부 10초가
      //   사실상 죽은 코드였음. 이제 내부 timeLimit 을 외부와 동일한 8초로
      //   넘겨 단일 진실 원천(_kGpsLookupTimeout)으로 통일.
      //   외부 .timeout()은 geolocator 가 timeLimit 을 무시할 수 있는
      //   웹/플랫폼 엣지 케이스 안전망으로 유지(이중 방어).
      Position? hostPos;
      try {
        hostPos = await _geoService
            .getCurrentPosition(timeLimit: _kGpsLookupTimeout)
            .timeout(_kGpsLookupTimeout, onTimeout: () {
          debugPrint('[SessionCreate] GPS 조회 ${_kGpsLookupTimeout.inSeconds}초 타임아웃 — null로 폴백');
          return null;
        });
        debugPrint(
          hostPos == null
              ? '[SessionCreate] GPS_UNAVAILABLE'
              : '[SessionCreate] GPS_AVAILABLE',
        );
      } catch (_) {
        debugPrint('[SessionCreate] GPS_LOOKUP_FAILED');
        hostPos = null;
      }

      // ── 4. 세션 생성 API 호출 ─────────────────────────
      debugPrint('[SessionCreate] POST /sessions 호출');
      final session = await _sessionsApi.createSession(
        accessToken:   token,
        name:          name,
        scheduledAt:   scheduledAt,
        radius:        radius,
        budget:        budget,
        returnMinutes: returnMinutes,
        memo:          memo.isEmpty ? null : memo,
        lat:           hostPos?.latitude,
        lng:           hostPos?.longitude,
      );

      if (!mounted) return;

      if (session == null) {
        debugPrint('[SessionCreate] createSession 응답 null — 실패 처리');
        _showError('세션을 만들지 못했어요. 잠시 후 다시 시도해봐요');
        return;
      }
      debugPrint('[SessionCreate] SESSION_CREATE_SUCCEEDED');

      // ── 5. 초대코드 생성 ──────────────────────────────
      debugPrint('[SessionCreate] POST /invitations 호출');
      final invitation = await _invitationsApi.createInvitation(
        accessToken: token,
        sessionId:   session.id,
      );

      if (!mounted) return;

      if (invitation == null) {
        debugPrint('[SessionCreate] createInvitation 응답 null — 실패 처리');
        _showError('초대 코드를 만들지 못했어요. 다시 시도해봐요');
        return;
      }
      debugPrint('[SessionCreate] INVITATION_CREATE_SUCCEEDED');

      // ── 6. 세션 생성 완료 → sessionProvider 초기화 후 로비 진입 ──
      // selectedMembers는 이미 역할을 다했으므로 초기화.
      // clearSession에서 예외가 나도 라우팅은 진행되도록 try로 보호.
      try {
        ref.read(sessionProvider.notifier).clearSession();
      } catch (_) {
        debugPrint('[SessionCreate] SESSION_STATE_CLEAR_FAILED');
      }

      if (!mounted) return;
      debugPrint('[SessionCreate] SessionLobbyScreen으로 라우팅');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SessionLobbyScreen(
            sessionId:      session.id,
            inviteCode:     invitation.inviteCode,
            initialSession: session, // 생성 응답을 바로 넘겨 재조회 생략
          ),
        ),
      );
    } catch (_) {
      // ── 예외 안전망 ─────────────────────────────────
      // API 서비스 내부에서 잡지 못한 예외나 라우팅/Provider 단계의 예외가
      // 여기로 올라오면 사용자에게 안내하고 로딩 상태를 반드시 해제한다.
      debugPrint('[SessionCreate] SESSION_CREATE_UNEXPECTED_FAILURE');
      if (mounted) {
        _showError('세션을 만드는 중 문제가 생겼어요. 다시 시도해봐요');
      }
    } finally {
      // ── 로딩 상태 복귀 보장 ────────────────────────
      // pushReplacement 이후에도 mounted면 setState 호출 가능.
      // 라우팅 성공 시에는 위젯이 unmount되므로 mounted=false → no-op.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── 에러 스낵바 헬퍼 ─────────────────────────────────
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── UI ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 선택된 멤버 목록은 sessionProvider에서 읽음 (CU-08에서 저장된 값)
    final selectedMembers = ref.watch(sessionProvider).selectedMembers;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true),
      body: SafeArea(
        child: Column(
          children: [
            // ── 스크롤 가능한 폼 영역 ─────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.lg),

                    // ── 세션 생성 단계 표시바 ─────────
                    _buildStepIndicator(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── 화면 제목 ─────────────────────
                    _buildHeader(selectedMembers.length),

                    const SizedBox(height: AppSpacing.lg),

                    // ── 세션 이름 ─────────────────────
                    _buildSectionLabel('세션 이름'),
                    AppTextField(
                      controller: _nameController,
                      hint: '예: 팀 점심, 금요일 회식',
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 점심 시간 선택 ────────────────
                    _buildSectionLabel('점심 시간'),
                    _buildTimePicker(),

                    const SizedBox(height: AppSpacing.md),

                    // ── 반경 ──────────────────────────
                    _buildSectionLabel('식당 검색 반경'),
                    _buildNumberField(
                      controller: _radiusController,
                      hint:   '500',
                      suffix: 'm',
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 예산 ──────────────────────────
                    _buildSectionLabel('1인당 예산'),
                    _buildNumberField(
                      controller: _budgetController,
                      hint:   '15000',
                      suffix: '원',
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 복귀시간 ─────────────────────
                    _buildSectionLabel('복귀 여유 시간'),
                    _buildNumberField(
                      controller: _returnMinutesController,
                      hint:   '30',
                      suffix: '분',
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── 메모 ─────────────────────────
                    _buildSectionLabel('메모 (선택)'),
                    AppTextField(
                      controller: _memoController,
                      hint: '알레르기, 선호 음식 등 자유롭게 입력',
                      maxLines: 3,
                    ),

                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),

            // ── 하단 고정 버튼 영역 ────────────────────
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  // ── 단계 표시바 ──────────────────────────────────────
  // 2단계(조건)까지 활성화 → 1·2번 인덱스가 primary 색상
  Widget _buildStepIndicator() {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: List.generate(3, (index) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 4,
            decoration: BoxDecoration(
              color: index < 2 ? primary : AppColors.border,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
        ),
      )),
    );
  }

  // ── 화면 헤더 ────────────────────────────────────────
  // 선택된 멤버 수를 함께 표시해 사용자가 맥락을 잃지 않도록 함
  Widget _buildHeader(int memberCount) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 단계 레이블 행
        Row(
          children: [
            Text('1단계 인원',
                style: AppTextStyles.label.copyWith(color: AppColors.textHint)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·', style: AppTextStyles.label.copyWith(
                  color: AppColors.textHint)),
            ),
            Text('2단계 조건',
                style: AppTextStyles.label.copyWith(
                    color: primary, fontWeight: FontWeight.w700)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·', style: AppTextStyles.label.copyWith(
                  color: AppColors.textHint)),
            ),
            Text('3단계 AI추천',
                style: AppTextStyles.label.copyWith(color: AppColors.textHint)),
          ],
        ),
        const SizedBox(height: 8),
        Text('세션 조건을 설정해주세요', style: AppTextStyles.heading1),
        const SizedBox(height: 4),
        // 선택된 멤버 수 안내 — 0명이면 "나만" 표시
        Text(
          memberCount > 0
              ? '함께하는 멤버 $memberCount명과 조건을 맞춰볼게요'
              : '나 혼자 세션을 시작해요',
          style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ── 섹션 레이블 ──────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: AppTextStyles.label.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── 시간 선택 위젯 ────────────────────────────────────
  // 탭하면 showTimePicker 호출, 선택된 시간 또는 "오늘 중" 표시
  Widget _buildTimePicker() {
    final primary = Theme.of(context).colorScheme.primary;
    final label = _selectedTime == null
        ? '오늘 중 (탭하여 시간 설정)'
        : '오늘 ${_selectedTime!.format(context)}';

    return GestureDetector(
      onTap: _pickTime,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: _selectedTime != null ? primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded,
                size: 18,
                color: _selectedTime != null
                    ? primary
                    : AppColors.textHint),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: _selectedTime != null
                    ? AppColors.textPrimary
                    : AppColors.textHint,
              ),
            ),
            const Spacer(),
            // 시간이 선택된 경우 취소 버튼 표시
            if (_selectedTime != null)
              GestureDetector(
                onTap: () => setState(() => _selectedTime = null),
                child: Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textHint),
              ),
          ],
        ),
      ),
    );
  }

  // ── 숫자 입력 필드 (반경/예산/복귀시간 공통) ─────────
  // 숫자 키패드 + 단위 suffix 표시
  Widget _buildNumberField({
    required TextEditingController controller,
    required String hint,
    required String suffix,
  }) {
    return Row(
      children: [
        Expanded(
          child: AppTextField(
            controller: controller,
            hint:      hint,
            // 숫자만 입력 가능하도록 키보드 타입 및 입력 필터 설정
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(width: 8),
        // 단위 레이블 (예: 'm', '원', '분')
        SizedBox(
          width: 32,
          child: Text(
            suffix,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ── 하단 고정 버튼 영역 ──────────────────────────────
  // "조건 초기화" + "세션 만들기" 두 버튼을 세로로 배치
  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal, 12,
        AppSpacing.screenHorizontal, 32,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 조건 초기화 — 반경/예산/복귀시간을 기본값으로 되돌림
          AppOutlinedButton(
            label: '조건 초기화',
            onPressed: _isLoading ? null : _resetConditions,
          ),
          const SizedBox(height: 8),
          // 세션 만들기 — 모든 조건으로 세션 생성 후 로비 진입
          AppPrimaryButton(
            label: _isLoading ? '세션 생성 중...' : '세션 만들기',
            onPressed: _isLoading ? null : _handleCreate,
          ),
        ],
      ),
    );
  }
}
