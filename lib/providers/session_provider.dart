import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/member.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점심 세션 생성 흐름의 전역 상태 관리 (Riverpod)
//
// 담당 범위:
//   CU-08(멤버 선택) → sessionProvider에 저장
//   CU-09(세션 조건 설정, 우현호 담당) → sessionProvider에서 읽기
//
// 왜 전역 상태가 필요한가?
//   CU-08에서 선택된 멤버 목록이 CU-09, CU-10 등 이후 화면으로 전달되어야 합니다.
//   화면이 Navigator 스택으로 연결되어 있어 콜백만으로는 여러 단계를 넘기기 어렵고,
//   Riverpod Provider에 저장하면 어느 화면에서든 ref.watch/read로 접근할 수 있습니다.
//
// Notifier 패턴을 선택한 이유:
//   단순 StateProvider로도 가능하지만,
//   세션 관련 조작 로직(초기화, 멤버 추가/제거 등)이 늘어날 수 있어
//   Notifier 클래스로 비즈니스 로직을 한 곳에 모았습니다.
// ══════════════════════════════════════════════════════════


// ── 세션 생성 흐름 전체 상태 ────────────────────────────────
// 현재는 selectedMembers만 포함하지만, CU-09 연동 시 조건(반경/예산/속도) 등 필드 추가 예정
class SessionState {
  const SessionState({
    this.selectedMembers = const [], // CU-08에서 선택된 멤버 목록 (기본: 빈 리스트)
  });

  /// CU-08에서 최종 선택된 멤버 목록
  /// CU-09(세션 조건 설정)에서 "함께하는 멤버 목록"으로 표시됨
  final List<Member> selectedMembers;

  // ── 불변 상태 복사 헬퍼 ─────────────────────────────────
  // Riverpod 상태는 불변(immutable)이어야 함.
  // 일부 필드만 바꾸고 싶을 때 copyWith을 사용해 새 객체를 생성합니다.
  SessionState copyWith({List<Member>? selectedMembers}) {
    return SessionState(
      selectedMembers: selectedMembers ?? this.selectedMembers,
    );
  }
}


// ── SessionNotifier: SessionState를 조작하는 비즈니스 로직 ──
class SessionNotifier extends Notifier<SessionState> {

  /// Provider가 처음 생성될 때 초기 상태를 반환
  /// 앱 시작 시 선택된 멤버 없음 → 빈 SessionState
  @override
  SessionState build() => const SessionState();

  // ── CU-08 완료 시 호출 ────────────────────────────────────
  // 선택된 멤버 목록을 상태에 저장합니다.
  // 이후 CU-09(우현호 담당)에서 ref.watch(sessionProvider).selectedMembers 로 읽습니다.
  void setSelectedMembers(List<Member> members) {
    state = state.copyWith(selectedMembers: List.unmodifiable(members));
  }

  // ── 세션 초기화 ──────────────────────────────────────────
  // 세션이 완료되거나 취소될 때 상태를 초기화합니다.
  // TODO: CU-09 취소 버튼 또는 세션 완료 후 호출 연결 필요
  void clearSession() {
    state = const SessionState();
  }
}


// ── sessionProvider: 앱 전역에서 접근하는 Provider 인스턴스 ──
//
// 사용 방법:
//   - 상태 읽기(UI 반영):  ref.watch(sessionProvider).selectedMembers
//   - 메서드 호출(상태 변경): ref.read(sessionProvider.notifier).setSelectedMembers(members)
//
// 사용 화면:
//   - CU-08 member_select_screen.dart → setSelectedMembers 호출
//   - CU-09 session_create_screen.dart (우현호 담당) → selectedMembers 읽기
final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);