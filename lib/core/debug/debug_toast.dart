import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 개발 전용 — 화면 전환 시 화면 ID를 자동으로 표시하는 토스트 유틸
//
// 사용법:
//   StatefulWidget의 initState에서 아래처럼 호출:
//
//     @override
//     void initState() {
//       super.initState();
//       DebugToast.show(context, 'CU-08');
//     }
//
// kDebugMode란?
//   Flutter가 제공하는 빌드 모드 플래그.
//   'flutter run' (개발 중) → true
//   'flutter build --release' (실제 배포) → false
//   → 이 조건 덕분에 배포 빌드에서는 코드가 남아 있어도 토스트가 뜨지 않음.
//   → 하지만 개발 완료 후에는 이 파일과 각 화면의 호출 코드를 함께 삭제하는 것을 권장.
//
// TODO: 개발 완료 후 삭제 체크리스트
//   1. 이 파일(lib/core/debug/debug_toast.dart) 삭제
//   2. 각 화면 initState의 DebugToast.show(...) 호출 줄 삭제
//   3. 각 화면 상단의 import '...debug_toast.dart' 줄 삭제
// ══════════════════════════════════════════════════════════

class DebugToast {
  // 외부에서 DebugToast()로 인스턴스를 만들지 못하게 막음
  // (이 클래스는 DebugToast.show()처럼 직접 호출해서 씀)
  DebugToast._();

  /// 화면 ID를 하단에 잠깐 표시하는 토스트를 띄움
  ///
  /// [context] : 현재 화면의 BuildContext
  /// [screenId]: 표시할 화면 ID (예: 'CU-08', 'CU-03')
  ///
  /// 주의: initState에서 직접 호출하면 컨텍스트가 아직 준비되지 않아 오류 발생.
  ///   반드시 addPostFrameCallback 안에서 호출해야 함.
  ///   (첫 프레임이 그려진 직후 = 화면이 화면에 나타난 직후에 실행됨)
  static void show(BuildContext context, String screenId) {
    // 릴리즈 빌드에서는 아무것도 하지 않음
    if (!kDebugMode) return;

    // addPostFrameCallback: 현재 프레임 렌더링이 완전히 끝난 뒤 실행
    // initState 시점에는 Scaffold가 아직 트리에 없을 수 있어 직접 호출 불가
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // mounted 확인: 콜백 실행 시점에 위젯이 이미 화면에서 제거됐을 수 있음
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // ── 토스트 내용 ──────────────────────────────
          content: Row(
            mainAxisSize: MainAxisSize.min, // Row가 내용 크기만큼만 차지
            children: [
              // 작은 아이콘으로 "개발 전용" 임을 시각적으로 표시
              const Icon(
                Icons.developer_mode_rounded,
                size: 14,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                screenId,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  // TODO: 수치 확정 시 수정 — 폰트 크기 및 굵기
                ),
              ),
            ],
          ),

          // ── 표시 시간: 1.5초 후 자동으로 사라짐 ──────
          // TODO: 수치 확정 시 수정 — 너무 짧으면 못 볼 수 있음
          duration: const Duration(milliseconds: 1500),

          // SnackBarBehavior.floating: 하단 탭바 위에 떠서 표시됨
          // (fixed는 하단 탭바와 겹쳐서 탭바 위로 올라가지 않음)
          behavior: SnackBarBehavior.floating,

          // 토스트 크기를 텍스트에 맞게 작게 유지
          width: 120,

          // ── 배경색: 반투명 짙은 회색 ─────────────────
          // 앱 UI와 구분되도록 검정 계열 사용
          backgroundColor: const Color(0xCC222222),

          // 모서리를 둥글게 처리
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          // 토스트 터치 시 바로 사라지도록
          dismissDirection: DismissDirection.down,
        ),
      );
    });
  }
}