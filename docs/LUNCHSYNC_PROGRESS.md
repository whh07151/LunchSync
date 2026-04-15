# LunchSync 진행도
**최종 업데이트:** 2026-04-14 (CU-09·CU-10 완료 반영)
**기준:** 실제 코드 직접 확인 (추정/문서 기반 아님)

---

## 범례
| 아이콘 | 의미 |
|---|---|
| ✅ | 완료 (API 연결 포함) |
| ⚠️ UI | UI 완료, API 미연결 (Mock 데이터) |
| ⚠️ 부분 | 일부 API 연결, 일부 미연결 |
| ❌ | 미구현 |

---

## 손님앱 (CU)

| ID | 기능 | 상태 | 실제 코드 근거 |
|---|---|---|---|
| CU-01 | 스플래시/서비스 소개 | ✅ | splash_screen.dart — 탭 1회로 로그인 진입, onboarding_done SharedPreferences 저장 |
| CU-02 | 카카오 로그인 | ✅ | kakao_auth_service.dart + auth_api_service.dart — POST /auth/kakao 실 연결, 실기기 테스트 완료 |
| CU-03 | 기본 프로필 설정 | ✅ | condition_setup_screen.dart — `_handleComplete()`에서 PATCH /users/me 실 호출 (이름/소속 포함) |
| CU-05 | 기본 조건 설정 | ✅ | condition_setup_screen.dart — PATCH /users/me로 반경/예산/속도 DB 저장 완료 |
| CU-06 | 홈 대시보드 | ⚠️ 부분 | home_screen.dart — GET /users/me로 사용자 이름 조회 연결. 세션/AI추천 식당은 Mock |
| CU-07 | 친구 초대/링크 공유 | ✅ | invitations_api_service.dart — POST /invitations 실 연결. 초대코드 생성·클립보드 복사·join_session_screen에서 코드 입력 참가까지 완료 |
| CU-08 | 친구/멤버 리스트 | ⚠️ 부분 | member_select_screen.dart — "조건 설정하기" → SessionCreateScreen 라우팅 연결. "초대 링크 복사하기" → 세션 생성+초대코드 즉시 발급. 멤버 목록은 _mockFriends (GET /users 백엔드 미구현) |
| CU-09 | 점심 세션 생성 | ✅ | session_create_screen.dart — 이름·시간·반경·예산·복귀시간·메모 입력. POST /sessions + POST /invitations 실 연결 후 로비 진입. DB 컬럼(radius·budget·return_minutes·memo) 추가 완료 |
| CU-10 | 세션 로비 | ✅ | session_lobby_screen.dart — 호스트(초대코드 카드+복사)+참가자 모드 분기. 멤버 목록 3초 폴링. WidgetsBindingObserver로 백그라운드 시 폴링 자동 중단 |
| CU-13 | 식당 상세/비교 | ❌ | 미구현 (장다연 담당) |
| CU-14 | 투표 화면 | ❌ | 미구현 (안태환 담당). 백엔드 POST/GET /sessions/:id/votes, POST /sessions/:id/decide 구현 완료 |
| CU-16 | 메뉴 목록/장바구니 | ⚠️ UI | menu_screen.dart — UI+cartProvider 연결. 백엔드 GET /restaurants/:id/menus 구현됐으나 프론트 미연결 (Mock 데이터 유지) |
| CU-17 | 그룹 주문 검토 | ✅ | order_review_screen.dart — cartProvider 내용 표시 + 총액 계산. POST /orders 실 연결 (paymentMethod=TOSS). 알레르기/중복 충돌 경고는 백엔드 검증 후 표시 |
| CU-18 | 결제 방식 선택 | ✅ | order_review_screen.dart 내 통합 — Toss 결제위젯으로 단일화. sessionStorage에 JWT·orderId·amount 백업 후 toss-checkout.html로 전체 페이지 리다이렉트 |
| CU-19 | 결제 시스템 호출/완료 | ✅ | payment_success_screen.dart + payment_fail_screen.dart — Toss successUrl/failUrl 왕복 처리. POST /payments/confirm 실 연결. 결제 후 cartProvider 초기화. 실제 Toss 테스트 키 필요 (현재 docs 샘플 키) |
| CU-20 | 주문/예약 추적 | ❌ | 미구현 (안태환 담당) |
| CU-22 | 알림함 | ⚠️ UI | notification_screen.dart — UI+읽음처리 완료. _mockNotifications 사용, GET /notifications 미연결 |
| CU-23 | 내정보/설정 | ✅ | my_info_screen.dart — initState에서 GET /users/me 로드, 저장 시 PATCH /users/me 실 호출. 로그아웃 카카오 unlink 미구현 |

---

## 점주앱 (OW)

| ID | 기능 | 상태 | 비고 |
|---|---|---|---|
| OW-02 | 오늘 운영 대시보드 | ❌ | Q6 앱 분리 구조 팀 합의 전까지 착수 불가 |

---

## POS 웹 (POS)

| ID | 기능 | 상태 | 비고 |
|---|---|---|---|
| POS-07 | POS 주방 모드 | ❌ | 미구현 |
| POS-10 | 호출 결과 보드 | ❌ | 미구현 |

---

## 공통 모듈 (CORE) — 김지효 담당분만

| ID | 기능 | 상태 | 비고 |
|---|---|---|---|
| CORE-13 | 공통 디자인 시스템/테마 | ✅ | 컬러/타이포/버튼/네비게이션 완료 (2026-04-01) |

---

## 핵심 플로우 연결 현황

```
로그인 ✅ → 온보딩(프로필+조건) ✅ → 홈 ⚠️부분
  → 멤버선택 ⚠️부분 → 세션조건설정 ✅ → 세션로비 ✅
  → (초대코드로 참가 ✅)
  → AI추천 ⚠️부분(백엔드만) → 투표 ❌(백엔드만) → 메뉴선택 ⚠️UI
  → 주문/결제 ⚠️부분 → 주문추적 ❌
```

**현재 데모 가능 범위:** 로그인 → 온보딩 → 홈 → 멤버선택 → 세션조건설정 → 로비(초대코드 공유·멤버 폴링) → 코드로 참가 → 메뉴화면 → 주문결제(웹) → 내정보 수정

---

## 백엔드/인프라 현황

| 항목 | 상태 | 비고 |
|---|---|---|
| Supabase DB 스키마 | 확인 필요 | 명세서 기준 10개 테이블 생성 여부 미확인 |
| POST /auth/kakao | ✅ | 카카오 로그인 실동작 확인 |
| GET /users/me | ✅ | CU-06, CU-23에서 실 호출 확인 |
| PATCH /users/me | ✅ | CU-05, CU-23에서 실 호출 확인 |
| GET /users (멤버 목록) | ❌ | CU-08 Mock 상태. users.controller에 미구현 |
| POST /sessions | ✅ | sessions.controller — 세션 생성 |
| GET /sessions/today | ✅ | sessions.controller |
| GET /sessions/:id | ✅ | sessions.controller |
| PATCH /sessions/:id/status | ✅ | sessions.controller |
| GET /sessions/:id/members | ✅ | sessions.controller |
| POST /sessions/:id/members | ✅ | sessions.controller |
| DELETE /sessions/:id/members/:userId | ✅ | sessions.controller |
| POST /invitations | ✅ | invitations.controller — 초대코드 생성 |
| GET /invitations/:code | ✅ | invitations.controller |
| POST /invitations/:code/accept | ✅ | invitations.controller |
| GET /restaurants | ✅ | restaurants.controller |
| GET /restaurants/:id | ✅ | restaurants.controller |
| GET /restaurants/:id/menus | ✅ | restaurants.controller |
| GET /sessions/:id/recommendations | ✅ | recommendations.controller — 그룹 AI 추천 |
| POST /sessions/:id/votes | ✅ | votes.controller |
| GET /sessions/:id/votes | ✅ | votes.controller |
| POST /sessions/:id/decide | ✅ | votes.controller — 투표 결과 확정 |
| POST /orders | ✅ | orders.controller |
| GET /orders/today | ✅ | orders.controller |
| GET /orders/:id | ✅ | orders.controller |
| PATCH /orders/:id/status | ✅ | orders.controller |
| POST /payments/confirm | ✅ | payments.controller — Toss 승인 |
| GET /pos/restaurants/:id/orders | ✅ | pos.controller — POS 주문 목록 |
| GET /pos/restaurants/:id/stats | ✅ | pos.controller — 결제 통계 |
| PATCH /pos/orders/:id/status | ✅ | pos.controller |
| POST /pos/orders/:id/cancel | ✅ | pos.controller — 취소/환불 |
| 폴링 304 최적화 | ❌ | 미구현 |
| FCM 푸시 알림 | ❌ | 미구현 |

---

## 실서비스 전환 전 필수 수정 사항 (7가지)

| 항목 | 내용 |
|---|---|
| JWT 저장 방식 | 인메모리 → flutter_secure_storage로 교체 (앱 재실행 시 자동 로그인) |
| 백엔드 URL | ~~로컬 IP 하드코딩~~ → AWS 도메인으로 변경 완료 (3a30e95) |
| CORS | `origin: '*'` → POS 웹 실 도메인으로 제한 |
| JWT_SECRET | 약한 개발용 값 → 강력한 랜덤 문자열로 교체 |
| 디버깅 코드 | DebugToast, print문 전부 제거 |
| service_role 키 | 채팅에서 노출됨 → Supabase에서 재발급 권장 |
| POST /users | 온보딩용 별도 엔드포인트 구현 (현재는 PATCH /users/me로 대체 중) |

---

## 미결 사항

| 항목 | 내용 | 전제조건 |
|---|---|---|
| Q6 앱 분리 구조 | 손님앱/점주앱/POS 분리 방식 팀 합의 필요 | OW-02 착수 전 필수 |
| sessions 테이블 분리 | sessions/session_state/voting_round 분리 여부 | 팀 합의 필요 |
| 카카오 회원목록 미표시 | 개발자 콘솔 회원목록 미표시 원인 미확인 | 나중에 해결 |

---

*코드를 직접 읽어서 확인한 내용만 기재. 추정 상태는 "확인 필요"로 표기.*
*변경 발생 시 즉시 이 파일 업데이트.*