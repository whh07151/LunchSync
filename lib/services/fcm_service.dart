import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

// ══════════════════════════════════════════════════════════
// 파일 역할: FCM(Firebase Cloud Messaging) 통합 서비스
//
// 역할 분담:
//   - 단말 토큰 획득 (FirebaseMessaging.instance.getToken)
//   - 알림 권한 요청 (iOS/Web)
//   - 토큰을 백엔드(POST /api/users/me/fcm-token)에 저장
//   - foreground 메시지 핸들러 등록
//   - onTokenRefresh 시 백엔드 재저장
//
// 호출 시점:
//   - 로그인 성공 직후 (main.dart 또는 home 진입 시점)
//   - 자동 로그인 복원 직후
//
// 안전성:
//   - Firebase 미초기화 환경에서도 실패해도 throw 하지 않음
//   - 권한 거부 시에도 앱 흐름은 정상 진행
//
// 백엔드 연동:
//   - notifications.service.createNotification 이 호출될 때 자동으로 FCM 송신.
//     별도 호출 불필요. 토큰만 저장돼 있으면 됨.
// ══════════════════════════════════════════════════════════

class FcmService {
  const FcmService();

  // ── 권한 요청 + 토큰 발급 + 백엔드 저장 ───────────────
  // 로그인 성공 직후 1회 호출 권장.
  //
  // 반환: 발급된 FCM 토큰 (실패/권한거부 시 null)
  Future<String?> registerToken({required String accessToken}) async {
    // 웹은 캡스톤 범위에서 Firebase 미설정 (docs/LUNCHSYNC_AUTH_DECISION.md:
    // Firebase 는 테스트/비활성). web 푸시용 service worker 가 없어
    // 등록 시도 시 MIME 오류가 콘솔에 찍히므로 웹에서는 조용히 건너뛴다.
    // 네이티브 모바일 빌드는 정상 동작 (kIsWeb == false).
    if (kIsWeb) {
      return null;
    }
    try {
      final messaging = FirebaseMessaging.instance;

      // iOS / Web 은 알림 권한 명시 요청 — Android 는 자동 허용
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FcmService] 알림 권한 거부 — 토큰 발급 건너뜀');
        return null;
      }

      // 단말 토큰 발급 (Android: FCM Token, iOS: APNs→FCM, Web: VAPID 키 필요)
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FcmService] FCM 토큰 발급 실패 — null/empty');
        return null;
      }

      // 백엔드에 저장
      await _saveTokenToBackend(token: token, accessToken: accessToken);

      // 토큰 갱신 콜백 — 만료/단말 교체 시 자동 재저장
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('[FcmService] FCM 토큰 갱신 — 백엔드 재저장');
        _saveTokenToBackend(token: newToken, accessToken: accessToken);
      });

      return token;
    } catch (e) {
      // Firebase 미초기화 / 미지원 플랫폼 등에서 안전하게 swallow
      debugPrint('[FcmService] registerToken 예외 (무시): $e');
      return null;
    }
  }

  // ── 백엔드에 토큰 저장 ────────────────────────────────
  // POST /api/users/me/fcm-token { token }
  Future<void> _saveTokenToBackend({
    required String token,
    required String accessToken,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.backendBaseUrl}/users/me/fcm-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(AppConfig.apiTimeout);
      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          '[FcmService] 백엔드 저장 실패 ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[FcmService] 백엔드 저장 예외: $e');
    }
  }

  // ── foreground 메시지 핸들러 등록 ─────────────────────
  // 앱이 활성화돼 있는 동안 도착한 메시지는 OS 가 알림 표시를 안 하므로
  // 우리가 직접 SnackBar/배너로 보여주거나 화면 상태를 갱신해야 함.
  //
  // 본 메서드는 콜백을 등록하기만 함 — 실제 UI 처리는 콜백 안에서.
  void listenForeground(void Function(RemoteMessage) onMessage) {
    FirebaseMessaging.onMessage.listen(onMessage);
  }
}
