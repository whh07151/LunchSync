import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_api_service.dart';
import '../services/fcm_service.dart';
import '../services/kakao_auth_service.dart';
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
  static const restaurantId = 'ls_user_restaurant_id';
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
    this.restaurantId,
    this.email,
    this.phoneNumber,
    this.businessName,
    this.businessNumber,
    // 2026-05-31 CU-04 — 추천 엔진이 읽는 구조화 취향 데이터.
    // 화면 진입 시 GET /users/me 로 채워지고, 취향 설정 화면에서 갱신됨.
    this.tasteTags = const [],
    this.allergens = const [],
    this.dislikedCategories = const [],
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

  /// OWNER 가 운영하는 restaurants.id (운영자가 Supabase 콘솔에서 매핑).
  /// NULL 이면 사장 홈에서 "매장 매핑 대기" 안내 표시.
  final String? restaurantId;

  // ── 사장 내정보 탭 표시용 (인메모리 캐시, 영속화는 별도) ──
  final String? email;
  final String? phoneNumber;
  final String? businessName;    // OWNER 상호
  final String? businessNumber;  // OWNER 사업자등록번호

  // ── 2026-05-31 CU-04 — 손님 취향 (추천 엔진 입력) ──────────
  // 영속 저장은 하지 않음 (앱 시작 시 GET /users/me 재호출로 복원).
  // 빈 배열 = 미설정 또는 모두 해제 (두 케이스를 화면이 구분할 필요 없음).
  final List<String> tasteTags;          // 좋아하는 맛 (매콤/담백/짠/단/신/쓴)
  final List<String> allergens;          // 알레르기 식재료
  final List<String> dislikedCategories; // 비선호 음식 카테고리

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
    String? restaurantId,
    String? email,
    String? phoneNumber,
    String? businessName,
    String? businessNumber,
    List<String>? tasteTags,
    List<String>? allergens,
    List<String>? dislikedCategories,
  }) {
    return UserState(
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      org: org ?? this.org,
      profileImage: profileImage ?? this.profileImage,
      role: role ?? this.role,
      status: status ?? this.status,
      restaurantId: restaurantId ?? this.restaurantId,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      businessName: businessName ?? this.businessName,
      businessNumber: businessNumber ?? this.businessNumber,
      tasteTags: tasteTags ?? this.tasteTags,
      allergens: allergens ?? this.allergens,
      dislikedCategories: dislikedCategories ?? this.dislikedCategories,
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

    // FCM 단말 토큰 발급 + 백엔드 저장 (best-effort).
    // 실패해도 throw 안 함 — Firebase 미초기화/권한 거부 환경에서도 흐름 유지.
    unawaited(const FcmService().registerToken(accessToken: response.accessToken));
  }

  // ── DB 프로필 조회 후 상태 갱신 ──────────────────────────
  // UsersApiService.getMe() 성공 후 호출.
  // 기존 accessToken은 유지하고 DB 최신값으로 덮어씀.
  // restaurantId는 운영자가 콘솔에서 매핑한 결과를 즉시 반영하기 위해 매번 동기화.
  Future<void> setFromProfile(UserProfile profile) async {
    state = state.copyWith(
      name: profile.name,
      org: profile.org,
      profileImage: profile.profileImage,
      role: profile.role,
      status: profile.status,
      restaurantId: profile.restaurantId,
      email: profile.email,
      phoneNumber: profile.phoneNumber,
      businessName: profile.businessName,
      businessNumber: profile.businessNumber,
      // 2026-05-31 CU-04 — 매번 DB 값으로 덮어써서 캐시 동기화
      tasteTags: profile.tasteTags,
      allergens: profile.allergens,
      dislikedCategories: profile.dislikedCategories,
    );

    // restaurantId 변경분 영속화 (다음 자동 로그인 시 즉시 사용)
    final prefs = await SharedPreferences.getInstance();
    if (profile.restaurantId != null && profile.restaurantId!.isNotEmpty) {
      await prefs.setString(_PrefKeys.restaurantId, profile.restaurantId!);
    } else {
      await prefs.remove(_PrefKeys.restaurantId);
    }

    // 자동 로그인 복원 흐름에서도 FCM 토큰을 재확보 (단말 교체/앱 재설치 대응).
    // 토큰이 동일하면 백엔드는 그냥 덮어쓰기 — 무해.
    final token = state.accessToken;
    if (token != null && token.isNotEmpty) {
      unawaited(const FcmService().registerToken(accessToken: token));
    }
  }

  // ── 2026-05-31 CU-04 — 취향 설정 저장 후 캐시 갱신 ────────
  // 취향 설정 화면(PreferencesScreen) 의 저장 성공 콜백에서 호출.
  // PATCH /users/me/preferences 응답을 그대로 반영해서
  // 추천 화면이 다음 렌더링에서 새 가중치를 적용하도록 함.
  void setPreferences({
    required List<String> tasteTags,
    required List<String> allergens,
    required List<String> dislikedCategories,
  }) {
    state = state.copyWith(
      tasteTags: tasteTags,
      allergens: allergens,
      dislikedCategories: dislikedCategories,
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
      restaurantId: prefs.getString(_PrefKeys.restaurantId),
    );
    return true;
  }

  // ── 로그아웃 시 유저 정보 초기화 ─────────────────────────
  // 인메모리 + SharedPreferences 둘 다 삭제 + 카카오 SDK 토큰도 만료.
  //
  // 카카오 logout() 은 try/catch 로 감싸져 있어 카카오 로그인 사용자가 아니어도
  // (이메일·휴대폰 가입) 안전하게 호출 가능. 미카카오 사용자 케이스는 무해하게
  // 무시됨.
  Future<void> clear() async {
    // 카카오 SDK 측 토큰 만료 — 다음 카카오 로그인 시 계정 선택 화면 노출되도록
    await const KakaoAuthService().logout();

    state = const UserState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_PrefKeys.jwt);
    await prefs.remove(_PrefKeys.userId);
    await prefs.remove(_PrefKeys.userName);
    await prefs.remove(_PrefKeys.userProfile);
    await prefs.remove(_PrefKeys.userRole);
    await prefs.remove(_PrefKeys.userStatus);
    await prefs.remove(_PrefKeys.restaurantId);
  }
}


/// 앱 전역에서 로그인 유저 정보에 접근하는 Provider
final userProvider =
    NotifierProvider<UserNotifier, UserState>(UserNotifier.new);
