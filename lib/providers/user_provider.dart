import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_api_service.dart';
import '../services/users_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 로그인한 유저 정보 + JWT를 앱 전역에서 관리 (Riverpod)
//
// 저장 범위: 인메모리 (앱 종료 시 초기화됨)
// 이유: SharedPreferences 등 영구 저장은 팀 합의 후 일괄 적용 예정.
//       현재는 로그인할 때마다 인증 흐름을 거침.
//
// 담당 데이터:
//   - accessToken: 모든 API 요청 헤더에 포함 (Authorization: Bearer ...)
//   - userId, name, profileImage: 홈/프로필 화면에 표시
//   - isNewUser: 로그인 직후 온보딩 여부 판단
//
// 사용 방법:
//   - 로그인 완료 후: ref.read(userProvider.notifier).setUser(authResponse)
//   - JWT 읽기: ref.read(userProvider).accessToken
//   - 로그아웃: ref.read(userProvider.notifier).clear()
// ══════════════════════════════════════════════════════════

// 유저 상태 데이터 클래스
class UserState {
  const UserState({
    this.accessToken,
    this.userId,
    this.name,
    this.org,
    this.profileImage,
  });

  final String? accessToken;  // LunchSync JWT (API 요청 시 사용)
  final String? userId;       // Supabase users.id
  final String? name;         // 표시 이름
  final String? org;          // 소속 (온보딩 CU-03에서 입력, DB에서 조회)
  final String? profileImage; // 프로필 이미지 URL

  /// 로그인된 상태인지 여부
  bool get isLoggedIn => accessToken != null;

  UserState copyWith({
    String? accessToken,
    String? userId,
    String? name,
    String? org,
    String? profileImage,
  }) {
    return UserState(
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      org: org ?? this.org,
      profileImage: profileImage ?? this.profileImage,
    );
  }
}


class UserNotifier extends Notifier<UserState> {

  @override
  UserState build() => const UserState(); // 초기 상태: 로그아웃 상태

  // ── 로그인 완료 시 유저 정보 저장 ────────────────────────
  // AuthApiService.loginWithKakao() 성공 후 호출.
  // accessToken, userId, name, profileImage만 저장.
  // org 등 상세 정보는 setFromProfile()로 별도 갱신.
  void setUser(AuthResponse response) {
    state = UserState(
      accessToken: response.accessToken,
      userId: response.userId,
      name: response.name,
      profileImage: response.profileImage,
    );
  }

  // ── DB 프로필 조회 후 상태 갱신 ──────────────────────────
  // UsersApiService.getMe() 성공 후 호출.
  // 기존 accessToken은 그대로 유지하고 DB 최신값으로 덮어씀.
  void setFromProfile(UserProfile profile) {
    state = state.copyWith(
      name: profile.name,
      org: profile.org,
      profileImage: profile.profileImage,
    );
  }

  // ── 로그아웃 시 유저 정보 초기화 ─────────────────────────
  // CU-23 로그아웃 버튼 탭 시 호출
  void clear() {
    state = const UserState();
  }
}


/// 앱 전역에서 로그인 유저 정보에 접근하는 Provider
final userProvider =
    NotifierProvider<UserNotifier, UserState>(UserNotifier.new);
