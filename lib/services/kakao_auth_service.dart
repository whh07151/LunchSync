import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 카카오 로그인/로그아웃 비즈니스 로직 서비스
//
// 왜 별도 서비스 파일로 분리했나?
//   카카오 SDK 관련 코드가 UI 화면(login_screen.dart)에 직접 있으면
//   SDK가 바뀌거나 백엔드 연동이 추가될 때 UI까지 수정해야 함.
//   서비스 클래스로 분리하면 UI는 결과만 받고,
//   내부 구현만 교체하면 됩니다.
//
// 연관 파일:
//   - lib/features/auth/login_screen.dart (CU-02, 이 서비스를 호출)
//   - lib/providers/user_provider.dart (TODO: 로그인 결과를 캐싱, 안태환 API 완성 후)
// ══════════════════════════════════════════════════════════

/// 카카오 로그인 결과를 담는 데이터 클래스
///
/// 성공 시: kakaoUser에 사용자 정보, errorMessage는 null
/// 실패 시: kakaoUser는 null, errorMessage에 오류 내용
class KakaoLoginResult {
  const KakaoLoginResult({
    this.kakaoUser,
    this.errorMessage,
  });

  /// 로그인 성공 시 카카오에서 받아온 사용자 정보
  /// TODO: 안태환 씨 API 완성 후 → 이 정보를 POST /auth/kakao로 전송하고
  ///       서버에서 받은 LunchSync 유저 객체 + JWT로 교체
  final User? kakaoUser;

  /// 로그인 실패 시 오류 메시지 (사용자에게 표시용)
  final String? errorMessage;

  /// 로그인 성공 여부
  bool get isSuccess => kakaoUser != null;
}


/// 카카오 인증 관련 기능을 담당하는 서비스 클래스
class KakaoAuthService {
  const KakaoAuthService();

  // ── 카카오 로그인 ─────────────────────────────────────────
  // 동작 순서:
  //   1. 기기에 카카오톡이 설치되어 있으면 → 카카오톡 앱으로 로그인 시도
  //   2. 카카오톡 없거나 실패하면 → 카카오 웹 로그인으로 fallback
  //   3. 로그인 성공 후 → 카카오 사용자 정보(닉네임, 프로필 사진 등) 조회
  Future<KakaoLoginResult> login() async {
    try {
      // ── 카카오톡 앱 설치 여부 확인 ────────────────────────
      // isKakaoTalkInstalled(): 기기에 카카오톡 앱이 있는지 확인
      final kakaoTalkInstalled = await isKakaoTalkInstalled();

      if (kakaoTalkInstalled) {
        // ── 카카오톡 앱으로 로그인 ───────────────────────────
        try {
          await UserApi.instance.loginWithKakaoTalk();
        } catch (e) {
          // 카카오톡 앱이 있어도 로그인 실패하는 경우 (예: 사용자가 취소, 권한 오류 등)
          // → 웹 로그인으로 fallback
          await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        // ── 카카오톡 없음: 웹 브라우저로 로그인 ────────────────
        await UserApi.instance.loginWithKakaoAccount();
      }

      // ── 로그인 성공 후: 카카오 사용자 정보 조회 ──────────────
      // UserApi.instance.me(): 현재 로그인된 카카오 계정의 프로필 정보 반환
      // 반환되는 정보: kakaoId, nickname, profileImageUrl, email(선택동의)
      final user = await UserApi.instance.me();
      return KakaoLoginResult(kakaoUser: user);
    } catch (e) {
      // 로그인 전체 실패 (네트워크 오류, 사용자 취소 등)
      return KakaoLoginResult(
        errorMessage: '카카오 로그인에 실패했어요.\n잠시 후 다시 시도해주세요.',
      );
    }
  }

  // ── 카카오 로그아웃 ───────────────────────────────────────
  // 앱의 카카오 액세스 토큰을 만료시킵니다.
  // (카카오 계정 자체에서 로그아웃되는 것은 아님)
  // TODO: CU-23 내정보/설정 화면의 로그아웃 버튼에 연결
  Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (_) {
      // 로그아웃 실패해도 앱 내 상태는 초기화되어야 하므로 오류 무시
    }
  }

  // ── 현재 로그인 상태 확인 ─────────────────────────────────
  // 앱 재실행 시 자동 로그인 여부 판단에 사용
  // TODO: main.dart의 스플래시 → 홈 자동 이동 로직에 연결
  Future<bool> isLoggedIn() async {
    try {
      final token = await TokenManagerProvider.instance.manager.getToken();
      return token != null && token.accessToken.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}