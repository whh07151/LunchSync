import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme.dart';
import '../../providers/user_provider.dart';
import '../../services/users_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장 정보 수정 화면 (OwnerProfileEditScreen)
//
// 진입 경로:
//   - owner_home_screen 의 "내정보" 탭 → "정보 수정" 행 → 본 화면 push
//
// 수정 가능 필드 (PATCH /api/users/me):
//   - businessName   (상호)
//   - businessNumber (사업자등록번호)
//   - name           (사장 표시 이름)
//
// 저장 흐름:
//   1. 폼 검증 (필수: 상호, 사업자번호는 10자 숫자 권장)
//   2. UsersApiService.updateMe() 호출
//   3. 성공 시 GET /users/me 재조회 → UserNotifier.setFromProfile 으로 상태 동기화
//   4. 화면 pop + SnackBar 알림
//
// 비고:
//   - email / phoneNumber / restaurantId / role / status 는 운영자가 Supabase에서
//     관리하므로 본 화면에서는 표시만 하고 수정 불가.
// ══════════════════════════════════════════════════════════

class OwnerProfileEditScreen extends ConsumerStatefulWidget {
  const OwnerProfileEditScreen({super.key});

  @override
  ConsumerState<OwnerProfileEditScreen> createState() =>
      _OwnerProfileEditScreenState();
}

class _OwnerProfileEditScreenState
    extends ConsumerState<OwnerProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _businessNameController;
  late final TextEditingController _businessNumberController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(userProvider);
    // 초기값은 현재 UserState 캐시값으로. 비어있으면 빈 문자열.
    _nameController = TextEditingController(text: user.name ?? '');
    _businessNameController =
        TextEditingController(text: user.businessName ?? '');
    _businessNumberController =
        TextEditingController(text: user.businessNumber ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _businessNameController.dispose();
    _businessNumberController.dispose();
    super.dispose();
  }

  // ── 저장 처리 ────────────────────────────────────────
  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(userProvider);
    final token = user.accessToken;
    if (token == null) {
      // 비정상 — JWT 없이 이 화면에 진입할 수 없음
      _showError('로그인 상태가 만료됐어요. 다시 로그인해 주세요.');
      return;
    }

    setState(() => _isSaving = true);

    // 1) 사장 정보 PATCH
    const usersApi = UsersApiService();
    final ok = await usersApi.updateMe(
      accessToken: token,
      name: _nameController.text.trim(),
      businessName: _businessNameController.text.trim(),
      businessNumber: _businessNumberController.text.trim(),
    );

    if (!ok) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('정보 저장에 실패했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }

    // 2) 최신 프로필 재조회 → 전역 상태 동기화 (홈 표시값 즉시 갱신)
    final profile = await usersApi.getMe(token);
    if (profile != null) {
      await ref.read(userProvider.notifier).setFromProfile(profile);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('저장됐어요'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop(true); // pop 결과로 true 전달 — 호출 측에서 활용 가능
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        title: const Text('사장 정보 수정'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.md),

                // 읽기 전용 정보 카드 — 이메일/휴대폰/매장 매핑
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _readOnlyRow(
                        icon: Icons.mail_outline_rounded,
                        label: '이메일',
                        value: user.email ?? '-',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _readOnlyRow(
                        icon: Icons.phone_iphone_rounded,
                        label: '휴대폰',
                        value: user.phoneNumber ?? '-',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _readOnlyRow(
                        icon: Icons.store_rounded,
                        label: '매장 매핑',
                        value: (user.restaurantId != null &&
                                user.restaurantId!.isNotEmpty)
                            ? '연동됨'
                            : '대기 중',
                        valueColor: (user.restaurantId != null &&
                                user.restaurantId!.isNotEmpty)
                            ? primary
                            : AppColors.warning,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                Text(
                  '수정 가능한 항목',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),

                // 이름
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '사장 이름',
                    hintText: '예) 김사장',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '이름을 입력해 주세요'
                      : null,
                ),

                const SizedBox(height: AppSpacing.md),

                // 상호
                TextFormField(
                  controller: _businessNameController,
                  decoration: const InputDecoration(
                    labelText: '상호',
                    hintText: '예) 점심싱크 본점',
                    prefixIcon: Icon(Icons.storefront_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? '상호를 입력해 주세요'
                      : null,
                ),

                const SizedBox(height: AppSpacing.md),

                // 사업자등록번호
                TextFormField(
                  controller: _businessNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '사업자등록번호',
                    hintText: '예) 1234567890 (숫자만 10자리)',
                    prefixIcon: Icon(Icons.assignment_rounded),
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return '사업자번호를 입력해 주세요';
                    // 너무 빡빡한 검증은 데모를 막을 수 있으니 자릿수만 가볍게.
                    if (value.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
                      return '숫자 8자리 이상을 입력해 주세요';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: AppSpacing.xl),

                // 저장 버튼
                FilledButton.icon(
                  onPressed: _isSaving ? null : _handleSave,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_isSaving ? '저장 중…' : '저장'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),

                const SizedBox(height: AppSpacing.sm),
                Text(
                  '이메일/휴대폰/매장 매핑은 운영자가 관리합니다.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnlyRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
