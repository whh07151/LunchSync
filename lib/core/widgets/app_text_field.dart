import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 전체에서 공통으로 사용하는 텍스트 입력 필드 위젯
//
// 왜 직접 만드나?
//   Flutter 기본 TextField를 그냥 쓰면 매번 스타일을 지정해야 합니다.
//   여기서 라벨 표시, 힌트, 에러 메시지까지 포함한 완성형 입력창을 만들면
//   AppTextField(label: '이름', hint: '이름을 입력해주세요') 한 줄로 끝납니다.
//
// 사용 예)
//   - 이름 입력창
//   - 닉네임 입력창
//   - 검색창 (검색은 별도 AppSearchBar 사용)
// ══════════════════════════════════════════════════════════

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,        // 입력값을 프로그래밍으로 읽거나 제어할 때 사용
    this.label,             // 입력창 위에 표시되는 라벨 텍스트
    this.hint,              // 아무것도 안 입력했을 때 표시되는 안내 텍스트
    this.errorText,         // 유효성 검사 실패 시 표시할 에러 메시지
    this.helperText,        // 입력창 아래 작게 표시되는 도움말 텍스트
    this.prefixIcon,        // 입력창 왼쪽에 표시되는 아이콘
    this.suffixIcon,        // 입력창 오른쪽에 표시되는 아이콘 (예: 비밀번호 토글)
    this.obscureText = false,  // true면 비밀번호처럼 ●●●●로 표시
    this.keyboardType,      // 키보드 종류 (숫자, 이메일, 전화번호 등)
    this.textInputAction,   // 키보드 완료 버튼 종류 (다음, 완료, 검색 등)
    this.onChanged,         // 텍스트가 바뀔 때마다 호출되는 함수
    this.onSubmitted,       // 키보드의 완료 버튼을 눌렀을 때 호출되는 함수
    this.inputFormatters,   // 입력 형식 제한 (숫자만, 최대 자리수 등)
    this.maxLength,         // 최대 입력 글자 수
    this.enabled = true,    // false면 입력 불가 (회색으로 표시됨)
    this.readOnly = false,  // true면 읽기만 가능 (탭하면 onTap 실행)
    this.onTap,             // readOnly일 때 탭하면 실행할 함수
    this.maxLines = 1,      // 입력창 최대 줄 수 (메모 등 멀티라인 입력 시 3 이상)
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;   // ValueChanged<String> = String을 받는 함수 타입
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final int maxLines; // 기본 1줄, 멀티라인 입력 시 3 이상 지정

  @override
  Widget build(BuildContext context) {
    return Column(
      // crossAxisAlignment: Column의 가로 방향 정렬
      // start = 왼쪽 정렬 (라벨이 입력창 왼쪽에 맞춰짐)
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // 컬럼이 내용물 크기만큼만 차지
      children: [

        // 라벨이 있을 때만 표시
        if (label != null) ...[
          Text(
            label!,  // !는 "이 값은 null이 아님을 내가 보장한다"는 표시
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w500, // 라벨은 살짝 굵게
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6), // 라벨과 입력창 사이 6px 간격
        ],

        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          maxLines: maxLines,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          style: AppTextStyles.bodyMedium, // 입력 텍스트 스타일
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            counterText: '', // maxLength 표시(예: 0/20)를 숨김
            // 나머지 스타일은 app_theme.dart의 inputDecorationTheme에서 자동 적용됨
          ),
        ),
      ],
    );
  }
}
