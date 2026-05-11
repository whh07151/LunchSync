// ══════════════════════════════════════════════════════════
// 파일 역할: 플랫폼별 Firebase 초기화 옵션
//
// 수동 작성 사유:
//   flutterfire CLI 가 환경에 따라 동작 안 할 수 있어, Firebase 콘솔에서 받은
//   값(memory: project_firebase_credentials.md)을 직접 코드화.
//
// 지원 플랫폼:
//   - Web      : Firebase Web SDK Config (apiKey/appId/etc.)
//   - Android  : google-services.json 의 값 그대로
//   - iOS      : 자료 미수령 — 빌드 시 UnsupportedError (Mac 팀원 합류 후 채울 것)
//
// 사용:
//   main.dart 에서 Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
// ══════════════════════════════════════════════════════════

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase 초기화 옵션 — 플랫폼별 자동 선택
class DefaultFirebaseOptions {
  /// 현재 실행 중인 플랫폼에 맞는 FirebaseOptions 반환
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS 용 GoogleService-Info.plist 미수령 상태입니다. Mac 팀원 합류 후 추가하세요.',
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          '${defaultTargetPlatform.name} 플랫폼은 LunchSync 지원 대상이 아닙니다.',
        );
    }
  }

  /// Web 플랫폼 (Chrome) — 카카오 redirect URI(8080) 와 함께 사용
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBYQWec05XcfFMVmT_cMHd-8n4pfBN06x4',
    appId: '1:472348585865:web:e03cb5162ef5eed8367b58',
    messagingSenderId: '472348585865',
    projectId: 'lunchsync-cf32f',
    authDomain: 'lunchsync-cf32f.firebaseapp.com',
    storageBucket: 'lunchsync-cf32f.firebasestorage.app',
    measurementId: 'G-TJLS7YNYS7',
  );

  /// Android — google-services.json 값 그대로
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC_nKqFO8UHQDSTFxCiR05MvIPY9wJSnPw',
    appId: '1:472348585865:android:b37aed822baa2f89367b58',
    messagingSenderId: '472348585865',
    projectId: 'lunchsync-cf32f',
    storageBucket: 'lunchsync-cf32f.firebasestorage.app',
  );
}
