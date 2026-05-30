// LunchSync — Firebase Cloud Messaging service worker (no-op)
//
// 캡스톤 범위에서는 웹 푸시(Firebase Messaging)를 사용하지 않는다
// (docs/LUNCHSYNC_AUTH_DECISION.md: Firebase 테스트/비활성).
// 이 파일은 브라우저가 firebase-messaging-sw.js 를 요청했을 때
// SPA fallback(index.html, text/html)이 아니라 정상 JavaScript(MIME)
// 가 응답되도록 두는 방어용 no-op service worker 다.
//
// 운영 전환 시: 아래 주석을 해제하고 firebase 설정을 채워 실제
// 백그라운드 메시지 핸들러를 구현한다.
//
// importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
// importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');
// firebase.initializeApp({ /* firebaseConfig */ });
// firebase.messaging();

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
