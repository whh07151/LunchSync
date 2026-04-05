import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 앱 전체에서 공통으로 사용하는 상단 앱바(AppBar) 위젯 모음
//
// AppBar란?
//   화면 상단에 고정되는 바(bar)입니다.
//   왼쪽에 뒤로가기 버튼, 가운데/왼쪽에 제목, 오른쪽에 액션 버튼이 들어갑니다.
//
// PreferredSizeWidget을 구현하는 이유:
//   Flutter의 Scaffold는 appBar 자리에 PreferredSizeWidget 타입만 받습니다.
//   (높이를 미리 알아야 레이아웃을 계산할 수 있어서)
//   preferredSize를 통해 "내 키는 이만큼이에요"를 Scaffold에 알려줍니다.
//
// 위젯 종류:
//   AppCustomBar — 일반 앱바 (제목 + 뒤로가기 + 액션 버튼)
//   AppSearchBar — 검색 전용 앱바 (뒤로가기 + 검색 입력창)
// ══════════════════════════════════════════════════════════


// ─────────────────────────────────────────────────────────
// AppCustomBar: 기본 앱바
//
// 사용 예) 대부분의 화면 상단
// implements PreferredSizeWidget: Scaffold의 appBar에 넣을 수 있게 해주는 인터페이스
// ─────────────────────────────────────────────────────────
class AppCustomBar extends StatelessWidget implements PreferredSizeWidget {
  const AppCustomBar({
    super.key,
    this.title,           // 앱바에 표시할 제목 텍스트
    this.centerTitle = false, // true면 제목 가운데, false면 왼쪽 정렬
    this.leading,         // 앱바 왼쪽에 표시할 커스텀 위젯 (showBack이 false일 때)
    this.actions,         // 앱바 오른쪽에 표시할 버튼들 (알림, 검색, 더보기 등)
    this.showBack = false, // true면 왼쪽에 뒤로가기 버튼 자동 표시
    this.onBack,          // 뒤로가기 버튼 눌렀을 때 (미지정 시 이전 화면으로)
    this.bottom,          // 앱바 아래 추가 영역 (예: 탭바)
  });

  final String? title;
  final bool centerTitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final PreferredSizeWidget? bottom;

  // preferredSize: 이 위젯의 높이를 Scaffold에 알려주는 값
  // kToolbarHeight = Flutter 기본 앱바 높이 (56px)
  // bottom이 있으면 그 높이를 더함
  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // title이 있을 때만 텍스트 표시
      title: title != null
          ? Text(title!, style: AppTextStyles.heading3)
          : null,
      centerTitle: centerTitle,

      // showBack이 true면 뒤로가기 버튼, 아니면 leading 위젯 사용
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              color: AppColors.textPrimary,
              // onBack이 지정됐으면 그것 실행, 없으면 이전 화면으로 pop
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            )
          : leading,

      // automaticallyImplyLeading: Flutter가 자동으로 뒤로가기를 넣을지
      // showBack을 직접 제어하므로 false로 설정
      automaticallyImplyLeading: showBack,
      actions: actions,
      bottom: bottom,
      // 나머지 스타일은 app_theme.dart의 appBarTheme에서 자동 적용됨
    );
  }
}


// ─────────────────────────────────────────────────────────
// AppSearchBar: 검색 전용 앱바
//
// 사용 예) 식당 검색 화면, 친구 검색 화면
// 제목 자리에 텍스트 입력창이 들어가고 키보드가 자동으로 올라옴
// ─────────────────────────────────────────────────────────
class AppSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSearchBar({
    super.key,
    required this.hint,       // 검색창 안내 텍스트 (예: '식당 이름으로 검색')
    this.onChanged,           // 검색어가 바뀔 때마다 호출 (실시간 검색에 사용)
    this.onBack,              // 뒤로가기 버튼 눌렀을 때
    this.controller,          // 검색어를 프로그래밍으로 제어할 때 사용
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onBack;
  final TextEditingController? controller;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // 왼쪽: 뒤로가기 버튼
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        color: AppColors.textPrimary,
        onPressed: onBack ?? () => Navigator.of(context).pop(),
      ),

      // 제목 자리에 검색 입력창을 배치
      title: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,   // 화면이 열리면 키보드 자동 표시
        style: AppTextStyles.bodyLarge,
        decoration: const InputDecoration(
          // 검색창 내부의 모든 테두리 제거 (앱바 안에서는 테두리 불필요)
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          filled: false,
        ),
      ),
    );
  }
}
