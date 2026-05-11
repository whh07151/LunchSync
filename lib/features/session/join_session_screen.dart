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
