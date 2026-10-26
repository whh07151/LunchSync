import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../core/debug/debug_toast.dart';
import '../../providers/user_provider.dart';
import '../../services/invitations_api_service.dart'
    show InvitationsApiService, AcceptSuccess, AcceptDuplicate, AcceptInvalid;
import 'session_lobby_screen.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 초대코드 입력 후 세션 참가 화면
//
// 흐름:
//   코드 입력 → "참가하기" 버튼 → POST /invitations/:code/accept
//     성공 → SessionLobbyScreen (참가자 모드, inviteCode 없음)
//     실패 → 에러 메시지 표시
//
// WOW#8 자동 채움 (2026-05-31):
//   친구가 카카오톡으로 받은 shortLink (예: https://lunchsync.duckdns.org/j/ABCD12)
//   를 모바일 웹에서 열면 Flutter 가 라우팅하면서 ?code=ABCD12 쿼리가 붙는다.
//   initState 에서 Uri.base 를 파싱해 텍스트필드 초기값으로 채우면 손님은
//   바로 "참가하기" 만 누르면 된다. 실패(웹 아님 / 파라미터 없음) 시 빈 입력 폴백.
// ══════════════════════════════════════════════════════════

class JoinSessionScreen extends ConsumerStatefulWidget {
  const JoinSessionScreen({super.key});

  @override
  ConsumerState<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends ConsumerState<JoinSessionScreen> {

  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  static const _invitationsApi = InvitationsApiService();

  @override
  void initState() {
    super.initState();
    DebugToast.show(context, 'JOIN');
    // WOW#8: 초대 링크에서 들어온 경우 코드 자동 채움.
    // Uri.base 는 모든 플랫폼에서 안전하지만, 모바일 네이티브에선 보통
    // file:// 등이라 ?code 쿼리가 없어 자연스럽게 빈 입력으로 폴백한다.
    _maybePrefillFromUrl();
  }

  // ── WOW#8: URL 쿼리에서 초대 코드 자동 채움 ─────────────
  // 지원 패턴 (둘 다 ?code=XXXXXXXX 형태):
  //   1) 메인 호스트의 ?code= 쿼리 — 라우터가 그대로 노출
  //   2) shortLink `/j/XXXXXXXX` 경로 — 별도 라우팅이 없으면 SPA 진입 후
  //      마지막 path 세그먼트로 폴백 추출 (nginx 설정 미적용 환경 대비)
  // 잘못된 입력에 대한 방어:
  //   - 비어 있으면 폴백
  //   - 길이/문자 검증 없음 — 사용자가 그대로 보고 수정 가능해야 하므로
  //     서버에서 검증하도록 위임 (8자리 hex 가 아닌 코드도 자유로이 시도 가능)
  void _maybePrefillFromUrl() {
    try {
      final uri = Uri.base;
      // 1순위: 명시적 ?code= 쿼리
      final fromQuery = uri.queryParameters['code']?.trim();
      if (fromQuery != null && fromQuery.isNotEmpty) {
        debugPrint('[JoinScreen] INVITE_CODE_PREFILLED_FROM_QUERY');
        _codeController.text = fromQuery;
        return;
      }
      // 2순위: /j/XXXXXXXX 경로 — shortLink 의 정식 형태
      final segments = uri.pathSegments;
      final jIdx = segments.indexOf('j');
      if (jIdx >= 0 && jIdx + 1 < segments.length) {
        final fromPath = segments[jIdx + 1].trim();
        if (fromPath.isNotEmpty) {
          debugPrint('[JoinScreen] INVITE_CODE_PREFILLED_FROM_PATH');
          _codeController.text = fromPath;
          return;
        }
      }
    } catch (_) {
      // Uri.base 가 던질 수 있는 모든 예외 무시 — 빈 입력 폴백 자연스러움
      debugPrint('[JoinScreen] INVITE_CODE_PARSE_FAILED');
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── 참가 버튼 핸들러 ──────────────────────────────────
  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = '초대 코드를 입력해주세요.');
      return;
    }

    final token = ref.read(userProvider).accessToken;
    if (token == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _invitationsApi.acceptInvitation(
      accessToken: token,
      code: code,
    );

    if (!mounted) return;

    switch (result) {
      case AcceptSuccess(:final sessionId):
        // 참가 성공 → 로비 화면으로 이동 (참가자 모드)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionLobbyScreen(sessionId: sessionId),
          ),
        );

      case AcceptDuplicate():
        // 이미 참가한 멤버 — 본인이 만든 방 코드 입력 시 포함 🥚
        setState(() => _isLoading = false);
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('🤔'),
            content: const Text(
              '이미 이 방에 계신 것 같은데요?\n혹시... 본인이 만든 방 아닌가요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('아 맞다 ㅋㅋ'),
              ),
            ],
          ),
        );

      case AcceptInvalid():
        setState(() {
          _isLoading = false;
          _errorMessage = '유효하지 않거나 만료된 초대 코드예요.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppCustomBar(showBack: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),

              // ── 제목 ────────────────────────────────────
              Text('초대 코드 입력', style: AppTextStyles.heading1),
              const SizedBox(height: 8),
              Text(
                '친구에게 받은 8자리 코드를 입력하세요',
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── 코드 입력창 ──────────────────────────────
              AppTextField(
                controller: _codeController,
                hint: '예: a1b2c3d4',
                onChanged: (_) {
                  // 입력할 때마다 에러 메시지 초기화
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),

              // ── 에러 메시지 ──────────────────────────────
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],

              const Spacer(),

              // ── 참가 버튼 ────────────────────────────────
              AppPrimaryButton(
                label: _isLoading ? '참가 중...' : '참가하기',
                onPressed: _isLoading ? null : _handleJoin,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
