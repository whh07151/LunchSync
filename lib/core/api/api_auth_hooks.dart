import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: 401 자동 로그아웃 글로벌 콜백 (간이 인터셉터)
//
// 배경:
//   기존 13개 *_api_service.dart 가 각자 http.* 직접 호출 — 401 처리 패턴이
//   일관되지 않음. ApiClient 풀 마이그레이션은 회귀 위험이 커서, 메서드
//   시그니처는 그대로 두고 401 응답만 글로벌 콜백으로 모으는 절충안.
//
// 사용 패턴:
//   1) 앱 부팅 시(main.dart) 콜백 등록:
//        ApiAuthHooks.onUnauthorized = () async {
//          await ref.read(userProvider.notifier).clear();
//        };
//
//   2) 각 *_api_service.dart 에서 401 응답 감지 후 알림:
//        if (response.statusCode == 401) {
//          ApiAuthHooks.notifyUnauthorized();
//        }
//
// 동작 보장:
//   - AppConfig.autoLogoutOn401 = false 이면 호출돼도 무시.
//   - 콜백이 등록 안 됐으면 무시. 등록된 콜백이 throw 해도 흐름은 계속.
//   - 짧은 시간 안에 여러 번 호출돼도(여러 API 가 동시에 401) 안전:
//     중복 호출 자체는 허용하나, 토큰은 한 번 클리어되면 그대로라 부작용 없음.
//
// 의도적으로 안 한 것:
//   - 라우터 직접 이동(GlobalNavigatorKey) — 캡스톤 안정성 위해 보류.
//     userProvider.clear() 후 _RootNavigator 가 build 다시 되며 자연스럽게
//     LoginScreen 으로 빠지도록 의존.
// ══════════════════════════════════════════════════════════

/// 401 응답 시 호출될 콜백 시그니처.
typedef UnauthorizedHook = void Function();

class ApiAuthHooks {
  ApiAuthHooks._();

  /// 앱 부팅 시(main.dart) 1회 등록. 등록 전엔 알림이 무시됨.
  static UnauthorizedHook? onUnauthorized;

  /// 401 응답 감지 시 *_api_service.dart 가 호출.
  /// AppConfig.autoLogoutOn401=false 면 무시 — 디버깅용 비활성 가능.
  static void notifyUnauthorized() {
    if (!AppConfig.autoLogoutOn401) return;
    final cb = onUnauthorized;
    if (cb == null) return;
    try {
      cb();
    } catch (e) {
      debugPrint('[ApiAuthHooks] UNAUTHORIZED_CALLBACK_FAILED');
    }
  }

  /// 응답 statusCode 가 401 이면 notifyUnauthorized() 호출.
  /// 각 *_api_service.dart 에서 응답 받은 직후 한 줄로 호출:
  ///   `ApiAuthHooks.check(response.statusCode);`
  static void check(int statusCode) {
    if (statusCode == 401) notifyUnauthorized();
  }
}
