# origin/temp → feat/dayeon 머지 기록

**작업일:** 2026-04-19
**머지 커밋:** `d0c3359`
**목적:** hyunho의 GPS/지도/크롤링 기능과 dayeon의 seed/메뉴 분리 로직을 하나로 합침

---

## 1. 채택 기준

| 영역 | 채택 브랜치 | 이유 |
|---|---|---|
| GPS 서비스, 지도, 크롤링, 알림, 주문 추적, 식당 상세/비교 | **temp (hyunho)** | dayeon에 없던 신기능 |
| 식당별 메뉴 분리 로직 (`menu_screen.dart`) | **dayeon** | week2 작업물, temp는 mock 유지 |
| 확장 seed (18식당 × 3메뉴 = 54건), constants 7개, normalizer 확장 | **dayeon** | week2 작업물 |
| `home_screen.dart` | **temp** | GPS + 자동 크롤링 + API 호출 로직 채택. dayeon의 `_mockRestaurants` 제거 |

---

## 2. temp에서 들어온 신규 파일

**프론트 (13개):**
- `lib/services/geolocation_service.dart` — GPS (1회 스냅샷 + 실시간 스트림)
- `lib/services/crawl_api_service.dart`, `notifications_api_service.dart`, `recommendations_api_service.dart`, `external_map_launcher.dart`
- `lib/core/widgets/kakao_map/*` 3개 (mobile/web/widget)
- `lib/features/session/recommendation_map_screen.dart`, `recommendation_list_screen.dart`
- `lib/features/orders/order_list_screen.dart`, `order_tracking_screen.dart`
- `lib/features/restaurant/restaurant_detail_screen.dart`, `restaurant_comparison_screen.dart`
- `lib/features/payment/payment_webview_screen.dart`

**백엔드 (7개):**
- `backend/src/crawl/{controller,module,service}.ts`
- `backend/src/notifications/{controller,module,service}.ts`
- `backend/scripts/crawl-restaurants.ts`, `migrations/2026-04-19-add-sessions-lat-lng.sql`
- `backend/src/recommendations/recommendations.service.ts` — Haversine 반경 필터 추가

**의존성 추가 (pubspec.yaml):**
- `geolocator: ^13.0.2`
- `webview_flutter: ^4.13.1`
- `url_launcher: ^6.3.1`

**백엔드 의존성 추가 (package.json):**
- `@nestjs/serve-static: ^5.0.5`

---

## 3. 충돌 해결

| 파일 | 해결 |
|---|---|
| `lib/features/home/home_screen.dart` | temp 채택 (GPS+crawl+API). dayeon의 `_MockRestaurant` 클래스/데이터 제거. 실 API 응답으로 대체됨 |

그 외 파일은 모두 자동 머지 성공.

---

## 4. 수정한 오류 (5건 → 0건)

머지 직후 `flutter analyze` 경고 5건, 컴파일 오류 0건.

| 파일 | 이슈 | 수정 |
|---|---|---|
| `lib/features/session/join_session_screen.dart` | `AcceptInvitationResult` unused shown name | `show` 목록에서 제거 |
| `lib/features/session/member_select_screen.dart` | 불필요한 `flutter/services.dart` import | 삭제 |
| `lib/features/session/member_select_screen.dart` (3곳) | `use_build_context_synchronously` (BuildContext 파라미터에 대한 `mounted` 체크가 미흡) | `!mounted` → `!context.mounted`로 교체, 중복 체크 제거 |
| `backend/src/app.module.ts` | `@nestjs/serve-static` 모듈 미발견 | `npm install`로 node_modules 동기화 (package.json엔 이미 선언됨) |

---

## 5. 검증 결과

- `flutter analyze`: **No issues found**
- `npm run build` (backend): **성공**
- git 머지 자체는 DB를 건드리지 않음 (아키텍처 원칙 유지: Flutter → NestJS → Supabase)

---

## 6. 머지 후 수동 작업 필요

1. **Supabase DB 마이그레이션 실행**: `backend/scripts/migrations/2026-04-19-add-sessions-lat-lng.sql`을 Supabase SQL 에디터에 붙여넣고 Run
2. **카카오 로컬 API 키 설정**: `backend/.env`에 `KAKAO_REST_API_KEY` 추가 (크롤링용)
3. **실행 확인**: `flutter run -d chrome --web-port 8080` + `npm run start:dev`로 GPS 권한 허용 → 지도/식당 리스트 렌더 확인

---

## 7. 남은 이슈 (docs/LUNCHSYNC_PROGRESS.md 참조)

- `menu_screen.dart`는 여전히 seed 기반 (dayeon 로직 유지). 추후 `GET /restaurants/:id/menus` API 연동으로 교체 필요
- 크롤로 가져온 식당에는 메뉴가 없음 (카카오 로컬 API는 메뉴/가격 미제공) → AI 연동 또는 수동 입력 필요
