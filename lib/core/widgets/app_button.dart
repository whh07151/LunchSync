import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import '../theme/app_colors.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 전체에서 공통으로 사용하는 버튼 위젯 모음
//
// 왜 버튼을 직접 만드나?
//   Flutter 기본 버튼(ElevatedButton 등)을 그냥 쓰면 매번 스타일을
//   지정해야 합니다. 여기서 미리 스타일이 적용된 버튼을 만들어두면
//   앱 어디서든 AppPrimaryButton(label: '확인', onPressed: ...) 한 줄로
//   일관된 디자인의 버튼을 쓸 수 있습니다.
//
// 버튼 종류:
//   AppPrimaryButton  — 배경색 채워진 주요 버튼 (가장 중요한 액션)
//   AppOutlinedButton — 테두리만 있는 보조 버튼 (두 번째 중요 액션)
//   AppTextButton     — 텍스트만 있는 버튼 (건너뛰기, 취소 등)
//   AppIconButton     — 아이콘 + 텍스트 버튼 (카카오 로그인 등)
//   AppChip           — 태그/필터 선택 칩
// ══════════════════════════════════════════════════════════


// ─────────────────────────────────────────────────────────
// AppPrimaryButton: 주요 CTA(Call To Action) 버튼
//
// 사용 예) '시작하기', '다음', '투표하기' 등 화면의 핵심 액션 버튼
// 배경색이 primary(주황/청록)로 채워진 형태
// ─────────────────────────────────────────────────────────
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,      // 버튼 안에 표시할 텍스트 (필수)
    required this.onPressed,  // 버튼을 눌렀을 때 실행할 함수 (필수)
    this.isLoading = false,   // true면 텍스트 대신 로딩 스피너 표시
    this.isEnabled = true,    // false면 버튼이 비활성화되어 누를 수 없음
    this.width,               // 버튼 가로 크기 (미지정 시 가로 꽉 참)
    this.height = 52,         // 버튼 세로 크기 (기본 52px)
  });

  final String label;
  final VoidCallback? onPressed; // VoidCallback = 아무것도 반환하지 않는 함수 타입
  final bool isLoading;
  final bool isEnabled;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity, // width가 null이면 가로 꽉 참
      height: height,
      child: ElevatedButton(
        // isEnabled가 false이거나 로딩 중이면 null을 넘겨 버튼 비활성화
        // Flutter에서 onPressed가 null이면 자동으로 비활성화 상태가 됨
        onPressed: (isEnabled && !isLoading) ? onPressed : null,
        child: isLoading
            // 로딩 중일 때: 흰색 동그란 스피너 표시
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            // 평상시: 텍스트 표시
            : Text(label),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppOutlinedButton: 보조 버튼 (Outlined = 테두리만 있는 형태)
//
// 사용 예) '건너뛰기', '나중에', '비교 추가' 등 주요 버튼 옆에 쓰는 버튼
// 배경이 투명하고 테두리만 primary 색으로 표시
// ─────────────────────────────────────────────────────────
class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
    this.width,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: isEnabled ? onPressed : null,
        child: Text(label),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppTextButton: 텍스트만 있는 버튼
//
// 사용 예) '비밀번호 찾기', '회원가입', '나중에 하기' 등
// 배경/테두리 없이 텍스트만 표시 → 시각적으로 가장 약한 강조
// ─────────────────────────────────────────────────────────
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppIconButton: 아이콘 + 텍스트 조합 버튼
//
// 사용 예) 카카오 로그인, 애플 로그인 등 소셜 로그인 버튼
// 왼쪽에 아이콘, 오른쪽에 텍스트 형태
// ─────────────────────────────────────────────────────────
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.icon,            // 버튼 왼쪽에 표시할 아이콘 위젯
    this.backgroundColor,          // 버튼 배경색 (미지정 시 흰색)
    this.foregroundColor,          // 텍스트/아이콘 색 (미지정 시 거의 검정)
    this.borderColor,              // 테두리 색 (미지정 시 연한 회색)
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor ?? AppColors.textPrimary,
          side: BorderSide(color: borderColor ?? AppColors.border),
        ),
        icon: icon,
        label: Text(
          label,
          style: AppTextStyles.buttonMedium.copyWith(
            color: foregroundColor ?? AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppChip: 선택 가능한 태그/필터 칩
//
// 사용 예) 음식 카테고리 필터(한식, 중식, 일식...), 반경 선택(500m, 1km...)
// 선택된 상태(isSelected=true)일 때 배경이 primary 색으로 채워짐
// ─────────────────────────────────────────────────────────
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.isSelected = false, // 현재 선택된 상태인지 여부
    this.onTap,              // 칩을 탭했을 때 실행할 함수
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 현재 테마의 primary 색을 가져옴
    // (손님앱이면 주황, 점주앱이면 청록이 자동으로 들어옴)
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      // GestureDetector: 탭, 스와이프 등 제스처를 감지하는 위젯
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 4, // 좌우 안쪽 여백 12px
          vertical: AppSpacing.xs + 2,   // 상하 안쪽 여백 6px
        ),
        decoration: BoxDecoration(
          // 선택됐으면 primary 색, 아니면 연한 회색 배경
          color: isSelected ? primary : AppColors.backgroundGrey,
          borderRadius: BorderRadius.circular(AppSpacing.xl), // 많이 둥근 모양
          border: Border.all(
            // 선택됐으면 primary 테두리, 아니면 회색 테두리
            color: isSelected ? primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            // 선택됐으면 흰색 텍스트, 아니면 보조 텍스트 색(회색)
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
