# LunchSync 캡처 모음 (제출용)

_생성 시각: 2026-05-13 16:39:34_

Flutter + NestJS 기반 점심 약속 통합 앱.
손님앱 / 사장앱 / POS 단말 세 가지 모두 캡처 포함.

## 📂 카테고리 목차

- [1. 인증 / 회원가입 / 로그인](#01auth) — 24장
- [2. 손님 홈 화면 / 탭](#02customerhome) — 21장
- [3. 점심 세션 (생성·로비·AI 추천·투표)](#03session) — 18장
- [4. 식당 / 메뉴 화면](#04restaurantmenu) — 3장
- [5. 결제 / 주문](#05paymentorder) — 7장
- [6. 사장 화면](#06owner) — 0장
- [7. POS 단말 (LunchSync-LSPOS)](#07pos) — 11장
- [9. 기타 (반응형 / 부팅 / 임시)](#99misc) — 20장

**총 104장**

---

## 1. 인증 / 회원가입 / 로그인  <a id='01auth'></a>

_스플래시, 온보딩, 로그인 화면, 회원가입 폼(손님/사장), 이메일 OTP, 휴대폰 인증, 카카오 로그인 버튼_

### 01-splash.png

![01-splash.png](screenshots/01-auth/01-splash.png)

### 02-login.png

![02-login.png](screenshots/01-auth/02-login.png)

### 03-login-demo.png

![03-login-demo.png](screenshots/01-auth/03-login-demo.png)

### 04-kakao-splash.png

![04-kakao-splash.png](screenshots/01-auth/04-kakao-splash.png)

### 05-kakao-after-splash.png

![05-kakao-after-splash.png](screenshots/01-auth/05-kakao-after-splash.png)

### 06-kakao-after-click.png

![06-kakao-after-click.png](screenshots/01-auth/06-kakao-after-click.png)

### 07-flow-splash.png

![07-flow-splash.png](screenshots/01-auth/07-flow-splash.png)

### 08-flow-login.png

![08-flow-login.png](screenshots/01-auth/08-flow-login.png)

### 09-vis-splash.png

![09-vis-splash.png](screenshots/01-auth/09-vis-splash.png)

### 0a-vis-login.png

![0a-vis-login.png](screenshots/01-auth/0a-vis-login.png)

### 0b-first-screen.png

![0b-first-screen.png](screenshots/01-auth/0b-first-screen.png)

### 0c-login-screen.png

![0c-login-screen.png](screenshots/01-auth/0c-login-screen.png)

### 0d-test-splash.png

![0d-test-splash.png](screenshots/01-auth/0d-test-splash.png)

### 0e-test-login.png

![0e-test-login.png](screenshots/01-auth/0e-test-login.png)

### 0f-test-login-viewport.png

![0f-test-login-viewport.png](screenshots/01-auth/0f-test-login-viewport.png)

### 10-phone-verify.png

![10-phone-verify.png](screenshots/01-auth/10-phone-verify.png)

### 20-login-fresh.png

![20-login-fresh.png](screenshots/01-auth/20-login-fresh.png)

### 21-signup-empty.png

![21-signup-empty.png](screenshots/01-auth/21-signup-empty.png)

### 22-signup-customer.png

![22-signup-customer.png](screenshots/01-auth/22-signup-customer.png)

### 23-signup-owner-toggle.png

![23-signup-owner-toggle.png](screenshots/01-auth/23-signup-owner-toggle.png)

### 24-signup-owner-filled.png

![24-signup-owner-filled.png](screenshots/01-auth/24-signup-owner-filled.png)

### 25-email-otp.png

![25-email-otp.png](screenshots/01-auth/25-email-otp.png)

### 26-kakao-button.png

![26-kakao-button.png](screenshots/01-auth/26-kakao-button.png)

### 27-kakao-click.png

![27-kakao-click.png](screenshots/01-auth/27-kakao-click.png)

---

## 2. 손님 홈 화면 / 탭  <a id='02customerhome'></a>

_홈 화면, 알림, 네 개 탭(점심세션·주문현황·내역·내정보), 카카오맵 영역_

### 10-home.png

![10-home.png](screenshots/02-customer-home/10-home.png)

### 11-home-full.png

![11-home-full.png](screenshots/02-customer-home/11-home-full.png)

### 12-home-phase4.png

![12-home-phase4.png](screenshots/02-customer-home/12-home-phase4.png)

### 13-notifications.png

![13-notifications.png](screenshots/02-customer-home/13-notifications.png)

### 14-home-after-login.png

![14-home-after-login.png](screenshots/02-customer-home/14-home-after-login.png)

### 15-home-current.png

![15-home-current.png](screenshots/02-customer-home/15-home-current.png)

### 16-home-scrolled-ai.png

![16-home-scrolled-ai.png](screenshots/02-customer-home/16-home-scrolled-ai.png)

### 17-home-with-session.png

![17-home-with-session.png](screenshots/02-customer-home/17-home-with-session.png)

### 18-tab-lunch-session.png

![18-tab-lunch-session.png](screenshots/02-customer-home/18-tab-lunch-session.png)

### 19-tab-orders.png

![19-tab-orders.png](screenshots/02-customer-home/19-tab-orders.png)

### 20-tab-history.png

![20-tab-history.png](screenshots/02-customer-home/20-tab-history.png)

### 21-tab-profile.png

![21-tab-profile.png](screenshots/02-customer-home/21-tab-profile.png)

### 22-verify-home.png

![22-verify-home.png](screenshots/02-customer-home/22-verify-home.png)

### 23-verify-full.png

![23-verify-full.png](screenshots/02-customer-home/23-verify-full.png)

### 24-sim-home.png

![24-sim-home.png](screenshots/02-customer-home/24-sim-home.png)

### 25-sim-home-loaded.png

![25-sim-home-loaded.png](screenshots/02-customer-home/25-sim-home-loaded.png)

### 26-browse-mode.png

![26-browse-mode.png](screenshots/02-customer-home/26-browse-mode.png)

### 27-vis-final.png

![27-vis-final.png](screenshots/02-customer-home/27-vis-final.png)

### 28-vis-browse.png

![28-vis-browse.png](screenshots/02-customer-home/28-vis-browse.png)

### 29-demo-final.png

![29-demo-final.png](screenshots/02-customer-home/29-demo-final.png)

### 2a-demo-browse.png

![2a-demo-browse.png](screenshots/02-customer-home/2a-demo-browse.png)

---

## 3. 점심 세션 (생성·로비·AI 추천·투표)  <a id='03session'></a>

_세션 생성 3단계, 로비, 멤버 입장, AI 추천 카드, 점수, 투표 시작, 결과, 경로 안내_

### 30-session-detail.png

![30-session-detail.png](screenshots/03-session/30-session-detail.png)

### 31-ai-recommendations.png

![31-ai-recommendations.png](screenshots/03-session/31-ai-recommendations.png)

### 32-vote-result.png

![32-vote-result.png](screenshots/03-session/32-vote-result.png)

### 33-session-create-step1.png

![33-session-create-step1.png](screenshots/03-session/33-session-create-step1.png)

### 34-session-create-step2.png

![34-session-create-step2.png](screenshots/03-session/34-session-create-step2.png)

### 35-after-create.png

![35-after-create.png](screenshots/03-session/35-after-create.png)

### 36-routing-result.png

![36-routing-result.png](screenshots/03-session/36-routing-result.png)

### 37-ai-scores.png

![37-ai-scores.png](screenshots/03-session/37-ai-scores.png)

### 38-ai-scores-final.png

![38-ai-scores-final.png](screenshots/03-session/38-ai-scores-final.png)

### 39-members-checked.png

![39-members-checked.png](screenshots/03-session/39-members-checked.png)

### 3a-session-detail-2.png

![3a-session-detail-2.png](screenshots/03-session/3a-session-detail-2.png)

### 3b-step2-conditions.png

![3b-step2-conditions.png](screenshots/03-session/3b-step2-conditions.png)

### 3c-step3-ai-recommend.png

![3c-step3-ai-recommend.png](screenshots/03-session/3c-step3-ai-recommend.png)

### 3d-step3-ai-after-wait.png

![3d-step3-ai-after-wait.png](screenshots/03-session/3d-step3-ai-after-wait.png)

### 3e-vote-start.png

![3e-vote-start.png](screenshots/03-session/3e-vote-start.png)

### 3f-ai-recommend.png

![3f-ai-recommend.png](screenshots/03-session/3f-ai-recommend.png)

### 3g-verify-ai-cards.png

![3g-verify-ai-cards.png](screenshots/03-session/3g-verify-ai-cards.png)

### 3h-sim-session-create.png

![3h-sim-session-create.png](screenshots/03-session/3h-sim-session-create.png)

---

## 4. 식당 / 메뉴 화면  <a id='04restaurantmenu'></a>

_식당 목록·상세, 메뉴 화면_

### 40-restaurant-detail.png

![40-restaurant-detail.png](screenshots/04-restaurant-menu/40-restaurant-detail.png)

### 41-menu-screen.png

![41-menu-screen.png](screenshots/04-restaurant-menu/41-menu-screen.png)

### 42-restaurant-new-copy.png

![42-restaurant-new-copy.png](screenshots/04-restaurant-menu/42-restaurant-new-copy.png)

---

## 5. 결제 / 주문  <a id='05paymentorder'></a>

_토스 위젯, 결제 성공/실패 콜백, Flutter 초기화면_

### 50-flutter-initial.png

![50-flutter-initial.png](screenshots/05-payment-order/50-flutter-initial.png)

### 51-toss-widget.png

![51-toss-widget.png](screenshots/05-payment-order/51-toss-widget.png)

### 52-error.png

![52-error.png](screenshots/05-payment-order/52-error.png)

### 53-success.png

![53-success.png](screenshots/05-payment-order/53-success.png)

### 54-fail.png

![54-fail.png](screenshots/05-payment-order/54-fail.png)

### 55-payment-success-new.png

![55-payment-success-new.png](screenshots/05-payment-order/55-payment-success-new.png)

### 56-payment-fail-new.png

![56-payment-fail-new.png](screenshots/05-payment-order/56-payment-fail-new.png)

---

## 6. 사장 화면  <a id='06owner'></a>

_사장 홈, 매출 통계, 주문 관리, 메뉴 편집, 승인 대기_

> ⚠️ (캡처 누락 — 추후 보충)

## 7. POS 단말 (LunchSync-LSPOS)  <a id='07pos'></a>

_POS 로그인, 대시보드, 주방 모드, 메뉴, 좌석, 주문, 매출, 예약_

### 70-pos-initial.png

![70-pos-initial.png](screenshots/07-pos/70-pos-initial.png)

### 71-pos-real.png

![71-pos-real.png](screenshots/07-pos/71-pos-real.png)

### 72-pos-login.png

![72-pos-login.png](screenshots/07-pos/72-pos-login.png)

### 73-pos-dashboard.png

![73-pos-dashboard.png](screenshots/07-pos/73-pos-dashboard.png)

### 74-pos-dashboard-v2.png

![74-pos-dashboard-v2.png](screenshots/07-pos/74-pos-dashboard-v2.png)

### 75-pos-kitchen.png

![75-pos-kitchen.png](screenshots/07-pos/75-pos-kitchen.png)

### 76-pos-menu.png

![76-pos-menu.png](screenshots/07-pos/76-pos-menu.png)

### 77-pos-seats.png

![77-pos-seats.png](screenshots/07-pos/77-pos-seats.png)

### 78-pos-orders.png

![78-pos-orders.png](screenshots/07-pos/78-pos-orders.png)

### 79-pos-stats.png

![79-pos-stats.png](screenshots/07-pos/79-pos-stats.png)

### 80-pos-reservations.png

![80-pos-reservations.png](screenshots/07-pos/80-pos-reservations.png)

---

## 9. 기타 (반응형 / 부팅 / 임시)  <a id='99misc'></a>

_반응형(데스크톱/태블릿/모바일), 부팅 화면, 임시 캡처_

### 90-after-back.png

![90-after-back.png](screenshots/99-misc/90-after-back.png)

### 91-after-click-1.png

![91-after-click-1.png](screenshots/99-misc/91-after-click-1.png)

### 92-after-create-click.png

![92-after-create-click.png](screenshots/99-misc/92-after-create-click.png)

### 93-boot-screen.png

![93-boot-screen.png](screenshots/99-misc/93-boot-screen.png)

### 94-after-boot.png

![94-after-boot.png](screenshots/99-misc/94-after-boot.png)

### responsive/desktop.png

![responsive/desktop.png](screenshots/99-misc/responsive/desktop.png)

### responsive/mobile-medium.png

![responsive/mobile-medium.png](screenshots/99-misc/responsive/mobile-medium.png)

### responsive/mobile-small.png

![responsive/mobile-small.png](screenshots/99-misc/responsive/mobile-small.png)

### responsive/sim-desktop.png

![responsive/sim-desktop.png](screenshots/99-misc/responsive/sim-desktop.png)

### responsive/sim-mobile-s.png

![responsive/sim-mobile-s.png](screenshots/99-misc/responsive/sim-mobile-s.png)

### responsive/sim-tablet.png

![responsive/sim-tablet.png](screenshots/99-misc/responsive/sim-tablet.png)

### responsive/tablet.png

![responsive/tablet.png](screenshots/99-misc/responsive/tablet.png)

### responsive/vis-desktop.png

![responsive/vis-desktop.png](screenshots/99-misc/responsive/vis-desktop.png)

### responsive/vis-mobile-m.png

![responsive/vis-mobile-m.png](screenshots/99-misc/responsive/vis-mobile-m.png)

### responsive/vis-mobile-s.png

![responsive/vis-mobile-s.png](screenshots/99-misc/responsive/vis-mobile-s.png)

### responsive/vis-tablet.png

![responsive/vis-tablet.png](screenshots/99-misc/responsive/vis-tablet.png)

### toss-docs/01-reference.png

![toss-docs/01-reference.png](screenshots/99-misc/toss-docs/01-reference.png)

### toss-docs/02-widget-admin.png

![toss-docs/02-widget-admin.png](screenshots/99-misc/toss-docs/02-widget-admin.png)

### toss-docs/03-sdk-v2-js.png

![toss-docs/03-sdk-v2-js.png](screenshots/99-misc/toss-docs/03-sdk-v2-js.png)

### toss-docs/04-widget-integration.png

![toss-docs/04-widget-integration.png](screenshots/99-misc/toss-docs/04-widget-integration.png)

---
