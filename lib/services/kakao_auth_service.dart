import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
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
/// 성공 시: kakaoAccessToken에 토큰 문자열, errorMessage는 null
/// 실패 시: kakaoAccessToken는 null, errorMessage에 오류 내용
class KakaoLoginResult {
  const KakaoLoginResult({
    this.kakaoAccessToken,
    this.errorMessage,
    this.isCancelled = false,
  });

  /// 카카오 SDK 로그인 성공 후 발급된 access token
  /// → POST /auth/kakao 요청 바디에 포함해서 LunchSync 서버로 전달
  final String? kakaoAccessToken;

  /// 로그인 실패 시 오류 메시지 (사용자에게 표시용)
  final String? errorMessage;

  /// 사용자가 카카오 인증 창을 닫은 경우. 오류 알림을 띄우지 않는다.
  final bool isCancelled;

  /// 로그인 성공 여부
  bool get isSuccess => kakaoAccessToken != null;
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
        } on KakaoAuthException catch (e) {
          // 사용자가 직접 취소한 경우 다른 로그인 창을 다시 열지 않는다.
          if (e.error == AuthErrorCause.accessDenied) rethrow;
          await UserApi.instance.loginWithKakaoAccount();
        } on KakaoClientException catch (e) {
          if (e.reason == ClientErrorCause.cancelled) rethrow;
          await UserApi.instance.loginWithKakaoAccount();
        } on PlatformException catch (e) {
          if (isKakaoLoginCancelled(e)) rethrow;
          await UserApi.instance.loginWithKakaoAccount();
        } catch (e) {
          // 카카오톡 앱이 있어도 로그인 실패하는 경우 (예: 사용자가 취소, 권한 오류 등)
          // → 웹 로그인으로 fallback
          await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        // ── 카카오톡 없음: 웹 브라우저로 로그인 ────────────────
        await UserApi.instance.loginWithKakaoAccount();
      }

      // ── 로그인 성공 후: 카카오 access token 추출 ──────────────
      // TokenManagerProvider: 카카오 SDK가 내부적으로 관리하는 토큰 저장소
      // getToken()으로 현재 발급된 access token을 가져옴
      // 이 토큰을 NestJS POST /auth/kakao에 전달해서 LunchSync JWT로 교환
      final token = await TokenManagerProvider.instance.manager.getToken();
      final accessToken = token?.accessToken;

      if (accessToken == null) {
        return const KakaoLoginResult(errorMessage: '카카오 토큰을 가져오지 못했어요.');
      }

      return KakaoLoginResult(kakaoAccessToken: accessToken);
    } catch (e) {
      if (isKakaoLoginCancelled(e)) {
        return const KakaoLoginResult(isCancelled: true);
      }
      debugPrint('[KakaoAuth] LOGIN_FAILED type=${e.runtimeType}');
      return KakaoLoginResult(errorMessage: kakaoLoginErrorMessage(e));
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

bool isKakaoLoginCancelled(Object error) =>
    (error is KakaoClientException &&
        error.reason == ClientErrorCause.cancelled) ||
    (error is KakaoAuthException &&
        error.error == AuthErrorCause.accessDenied) ||
    (error is PlatformException && error.code == 'CANCELED');

/// SDK 오류의 상세 내용에는 URL이나 계정 정보가 포함될 수 있어 안전한 안내만 표시한다.
String kakaoLoginErrorMessage(Object error) {
  if (error is KakaoClientException &&
      error.reason == ClientErrorCause.cancelled) {
    return '카카오 로그인이 취소됐어요.';
  }
  if (error is KakaoAuthException) {
    switch (error.error) {
      case AuthErrorCause.accessDenied:
        return '카카오 로그인이 취소됐어요.';
      case AuthErrorCause.misconfigured:
        return '현재 웹 주소 또는 앱이 카카오 개발자 설정에 등록되지 않았어요.';
      case AuthErrorCause.invalidClient:
        return '카카오 앱 키 설정이 맞지 않아요. 관리자에게 알려주세요.';
      case AuthErrorCause.unauthorized:
        return '카카오 로그인 사용 권한을 확인해 주세요.';
      default:
        break;
    }
  }
  return '카카오 로그인에 실패했어요. 잠시 후 다시 시도해주세요.';
}
