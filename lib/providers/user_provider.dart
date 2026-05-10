import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_api_service.dart';
import '../services/users_api_service.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 로그인한 유저 정보 + JWT를 앱 전역에서 관리 (Riverpod)
//
// 회원가입/인증 결정(2026-05-07) 반영:
//   - role / status 필드 추가 (CUSTOMER/OWNER · PENDING/APPROVED/REJECTED)
//   - SharedPreferences에 JWT 영속화 → 자동 로그인 지원
//
// 자동 로그인 흐름:
//   1. main()에서 _RootNavigator가 SharedPreferences에서 'ls_jwt' 조회
//   2. JWT가 있으면 GET /users/me 호출 → role/status 파악
//   3. 정상이면 손님/사장 홈으로 바로 진입, 토큰 만료면 로그인 화면
//
// 담당 데이터:
//   - accessToken: 모든 API 요청 헤더에 포함 (Authorization: Bearer ...)
//   - userId, name, profileImage, org: 화면 표시용
//   - role, status: 역할 분기 + 사장 승인 차단용
//
// 저장 위치:
//   - 인메모리(Riverpod state) + SharedPreferences(영속).
//   - setUser/clear 호출 시 자동으로 둘 다 동기화됨.
//
// 사용 방법:
//   - 로그인 완료 후: ref.read(userProvider.notifier).setUser(authResponse)
//   - JWT 읽기: ref.read(userProvider).accessToken
//   - 자동로그인 복원: ref.read(userProvider.notifier).restoreFromStorage()
//   - 로그아웃: ref.read(userProvider.notifier).clear()
// ══════════════════════════════════════════════════════════

// SharedPreferences 키 — 한 곳에서 관리해서 오타 방지
class _PrefKeys {
  static const jwt          = 'ls_jwt';
  static const userId       = 'ls_user_id';
  static const userName     = 'ls_user_name';
  static const userProfile  = 'ls_user_profile';
  static const userRole     = 'ls_user_role';
  static const userStatus   = 'ls_user_status';
}


// 유저 상태 데이터 클래스
class UserState {
  const UserState({
    this.accessToken,
    this.userId,
    this.name,
    this.org,
    this.profileImage,
    this.role,
    this.status,
  });

  final String? accessToken;  // LunchSync JWT (API 요청 시 사용)
  final String? userId;       // Supabase users.id
  final String? name;         // 표시 이름
  final String? org;          // 소속
  final String? profileImage; // 프로필 이미지 URL

  /// 'CUSTOMER' | 'OWNER'
  final String? role;

  /// 'PENDING' | 'APPROVED' | 'REJECTED' (OWNER 승인 차단 판단용)
  final String? status;

  /// 로그인된 상태인지 여부
  bool get isLoggedIn => accessToken != null;

  /// 사장(승인 완료) 여부 — 사장 홈 진입 가드용
  bool get isApprovedOwner => role == 'OWNER' && status == 'APPROVED';

  /// 사장(승인 대기) 여부 — 안내 화면 분기용
  bool get isPendingOwner => role == 'OWNER' && status != 'APPROVED';

  UserState copyWith({
    String? accessToken,
    String? userId,
    String? name,
    String? org,
    String? profileImage,
    String? role,
    String? status,
  }) {
    return UserState(
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      org: org ?? this.org,
      profileImage: profileImage ?? this.profileImage,
      role: role ?? this.role,
      status: status ?? this.status,
    );
  }
}


class UserNotifier extends Notifier<UserState> {

  @override
  UserState build() => const UserState(); // 초기 상태: 로그아웃

  // ── 로그인 완료 시 유저 정보 저장 ────────────────────────
  // AuthApiService.loginWithKakao() / signupEmail() / loginEmail() 성공 후 호출.
  // SharedPreferences에도 동기 백업 → 다음 앱 실행 시 자동 로그인.
  Future<void> setUser(AuthResponse response) async {
    state = UserState(
      accessToken: response.accessToken,
      userId: response.userId,
      name: response.name,
      profileImage: response.profileImage,
      role: response.role,
      status: response.status,
    );

    // 영속 저장 (자동 로그인용)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_PrefKeys.jwt, response.accessToken);
    await prefs.setString(_PrefKeys.userId, response.userId);
    await prefs.setString(_PrefKeys.userName, response.name);
    if (response.profileImage != null) {
      await prefs.setString(_PrefKeys.userProfile, response.profileImage!);
    } else {
      await prefs.remove(_PrefKeys.userProfile);
    }
    await prefs.setString(_PrefKeys.userRole, response.role);
    await prefs.setString(_PrefKeys.userStatus, response.status);
  }

  // ── DB 프로필 조회 후 상태 갱신 ──────────────────────────
  // UsersApiService.getMe() 성공 후 호출.
  // 기존 accessToken은 유지하고 DB 최신값으로 덮어씀.
  void setFromProfile(UserProfile profile) {
    state = state.copyWith(
      name: profile.name,
      org: profile.org,
      profileImage: profile.profileImage,
      role: profile.role,
      status: profile.status,
    );
  }

  // ── 결제 왕복 후 sessionStorage 에서 복원 ─────────────────
  // Flutter 웹은 토스 결제 페이지로 전체 리다이렉트될 때 앱이
  // 새로 로드돼 Riverpod 상태(특히 JWT)가 모두 날아갑니다.
  // 결제 직전에 sessionStorage 로 백업해둔 값을 앱 시작 시점에
  // 이 메서드로 복원해서 로그인 상태를 이어갑니다.
  void restoreFromSession({
    required String accessToken,
    String? userId,
    String? name,
    String? profileImage,
  }) {
    state = UserState(
      accessToken: accessToken,
      userId: userId,
      name: name,
      profileImage: profileImage,
      role: state.role,
      status: state.status,
    );
  }

  // ── 자동 로그인: SharedPreferences에서 복원 ──────────────
  // 앱 시작 시 main.dart의 _RootNavigator에서 호출.
  // 반환:
  //   true  — 토큰 복원 성공 (Riverpod state에 반영됨)
  //   false — 저장된 토큰이 없음 (로그인 화면으로)
  Future<bool> restoreFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString(_PrefKeys.jwt);
    if (jwt == null || jwt.isEmpty) return false;

    state = UserState(
      accessToken: jwt,
      userId: prefs.getString(_PrefKeys.userId),
      name: prefs.getString(_PrefKeys.userName),
      profileImage: prefs.getString(_PrefKeys.userProfile),
      role: prefs.getString(_PrefKeys.userRole),
      status: prefs.getString(_PrefKeys.userStatus),
    );
    return true;
  }

  // ── 로그아웃 시 유저 정보 초기화 ─────────────────────────
  // 인메모리 + SharedPreferences 둘 다 삭제.
  Future<void> clear() async {
    state = const UserState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_PrefKeys.jwt);
    await prefs.remove(_PrefKeys.userId);
    await prefs.remove(_PrefKeys.userName);
    await prefs.remove(_PrefKeys.userProfile);
    await prefs.remove(_PrefKeys.userRole);
    await prefs.remove(_PrefKeys.userStatus);
  }
}


/// 앱 전역에서 로그인 유저 정보에 접근하는 Provider
final userProvider =
    NotifierProvider<UserNotifier, UserState>(UserNotifier.new);
