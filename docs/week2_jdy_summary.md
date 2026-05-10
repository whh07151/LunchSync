# 장다연 2주차 산출물 요약

**작성일:** 2026-04-18
**브랜치:** `feat/dayeon`
**작업 범위:** Day 8~14 (식당 데이터 보강, 태그 체계, 추천 문구, 화면 기준 설정)

---

## 수정한 기존 파일 (4개)

### 1. `lib/data/seeds/restaurant_seeds.dart`
- 식당 6곳 추가 (rest_013 ~ rest_018): 교촌치킨, 하남돼지집, 쌈밥집, 신전떡볶이, 아웃백, CoCo이찌방야
- 기존 12곳의 구조(RestaurantSeed 필드) 변경 없음
- 카테고리 다양성 확보: 치킨, 고깃집, 건강식, 분식, 프리미엄 양식, 일본식 카레 추가
- 태그 품질 향상: chicken, meat, vegetable, snack, steak, curry, beer, custom 등 신규 태그 사용

### 2. `lib/data/seeds/menu_seeds.dart`
- 기존 2개뿐이던 식당 5곳에 메뉴 1개씩 추가 (rest_003, 005, 007, 009, 010 → 각각 3개로 보완)
- 신규 식당 6곳의 메뉴 각 3개씩 추가 (18건)
- 총 메뉴: 기존 31건 → 54건 (23건 추가)
- 기존 MenuSeed 구조(id, restaurantId, name, description, price, category) 변경 없음

### 3. `lib/core/utils/normalizer.dart`
- 기존 함수 6개 수정 없음
- 신규 함수 8개 추가:
  - `normalizeAllergen()` — 알레르기 원재료 정규화
  - `allergenLabel()` — 알레르기 코드 → 한글 라벨
  - `normalizeSpiceLevel()` — 맵기 레벨 정규화 (0~3)
  - `spiceLevelLabel()` — 맵기 레벨 → 한글 라벨
  - `distanceToWalkingLabel()` — 미터 → 도보 시간
  - `distanceLevel()` — 미터 → 가까움 레벨 (0~3)
  - `normalizeDietaryType()` — 식이제한 유형 정규화
  - `dietaryTypeLabel()` — 식이제한 코드 → 한글 라벨

### 4. `lib/core/constants/ui_texts.dart`
- 기존 DetailTexts, CompareTexts, RecommendTexts 수정 없음
- RecommendTexts에 문구 12개 추가 (카테고리별, 알레르기, 최근방문)
- 신규 클래스 2개 추가:
  - `DetailExtraTexts` — 리뷰 요약, 대표 메뉴, 영업 정보, 알레르기 안내 문구
  - `CompareExtraTexts` — 비교 표 추가 항목 (대표메뉴, 예산적합, 알레르기, 최근방문, 추천점수)

---

## 새로 생성한 파일 (6개)

### 5. `lib/core/constants/condition_tag_map.dart`
- 상황/조건 → 태그 매핑 (conditionTagMap): 15개 조건
  - 식사 인원: solo, group
  - 식사 속도: fast_meal, normal_meal, slow_meal
  - 식사 목적: light_meal, hearty_meal, budget_meal, premium_meal, healthy_meal, cafe_time
  - 분위기/상황: date, team_dinner, quick_lunch, rainy_day, hot_weather
- 유틸 함수: `speedToConditionKey()`, `budgetToConditionKey()`

### 6. `lib/core/constants/home_recommendation_config.dart`
- 홈 화면 추천 카드 표시 설정: maxCards, minScoreThreshold
- 필수/선택 필드 목록
- 상황별 제목 문구 8종
- 점수 구간별 라벨 + `scoreLabelFor()` 변환 함수

### 7. `lib/core/constants/menu_display_config.dart`
- 메뉴 카드 필드 표시 우선순위 (6단계)
- 맵기 배지 설정 (4단계, MenuSpiceBadge 클래스)
- 알레르겐 배지 설정 (주요 8종 + 라벨 맵)
- 품절 표시 규칙, 대표 메뉴 배지
- 카테고리 정렬 순서

### 8. `lib/core/constants/recommendation_texts.dart`
- RecommendReasonTexts: 추천 사유 상세 문구 17개 (예산, 거리, 취향, 혼밥, 단체, 속도, 건강)
- AvoidReasonTexts: 제외/회피 사유 상세 문구 14개 (예산초과, 거리, 알레르기, 최근방문, 비선호)
- RecommendSummaryTexts: 요약 문구 5개 + `summaryForScore()` 변환 함수

### 9. `lib/core/constants/recommendation_reason_categories.dart`
- ReasonCategory: 추천 근거 카테고리 정의 (id, label, icon, priority)
- 긍정 6종: budget_fit, distance_fit, taste_match, tag_match, solo_friendly, group_friendly
- 부정 5종: allergen_warning, budget_over, too_far, recent_visit, dislike_match
- 유틸: `findById()`, `positiveReasons`, `negativeReasons`
- RecommendationWeights: 추천 점수 가중치 상수 (backend 로직 대응)

### 10. `lib/core/constants/session_restaurant_config.dart`
- 세션-식당 연결 최소 필드 목록 3종 (추천용, 투표용, 메뉴전환용)
- 기본값: defaultRadiusMeters(500), defaultBudgetWon(15000), defaultReturnMinutes(30)
- `maxWalkingDistance()`: 복귀시간으로 최대 도보거리 계산
- 후보 수 설정: maxCandidates(10), minCandidates(2)
- 조건 완화 안내 문구

---

## 추가 작업: 식당��� 메뉴 분리 표시

### 5. `lib/features/menu/menu_screen.dart` (기존 화면 수정)
- **목적:** 홈 화면에서 어떤 식당을 눌러도 동일한 mock 메뉴 12개가 나���던 문제 해결
- **원인:** `MenuScreen`이 `restaurantName`만 ��고, ��부에 하드코딩된 `_mockMenuItems`를 항상 표시
- **수정 내용:**
  - `restaurant_seeds.dart`, `menu_seeds.dart` import 추가
  - `_menuItems` getter 추가: `restaurantName`으로 `restaurantSeeds`에서 식당 ID를 찾고, `menuSeeds`에서 해당 식당 메뉴만 필터링
  - `_mapSeedCategory()` 함수 추가: MenuSeed의 카테고리 문자열('밥류','면류' 등)을 MenuCategory enum으로 변환
  - `_filteredMenuItems`가 `_menuItems`를 참조하도록 변경
  - 앱바 메뉴 개수 표시�� 동적으로 변경
  - seed에 없는 식당은 기존 `_mockMenuItems` 12개를 fallback으로 표시
- **기존 코드 영향:** 기존 `_mockMenuItems`, 주문 흐름(`OrderReviewScreen` 연결), `cartProvider` 연동 등은 변경 없음
- **주의 (해결됨):** 프론트 seed ID와 DB UUID를 일치시켜 주문 흐름도 정상 동작하도록 수정 완료

---

## 추가 작업: 프론트↔DB UUID 통일 + 홈 식당 확장 + DB 시드

### 6. 프론트 seed ID를 UUID로 통일
- **restaurant_seeds.dart:** `rest_001` ~ `rest_018` → `bbbbbbbb-0000-4000-8000-000000000001` ~ `000000000018`
- **menu_seeds.dart:** `menu_NNN_MM` → `cccccccc-0NNN-4000-8000-0000000000MM`
- **목적:** 프론트에서 보여주는 메뉴 ID와 DB의 menu_items ID가 일치해야 주문(POST /orders)이 동작

### 7. `lib/features/home/home_screen.dart` (기존 화면 수정)
- **목적:** 홈 화면 AI 추천 식당을 3개 → 5개로 확장 (옆으로 스크롤)
- `_mockRestaurants`에 홍콩반점, 백소정 추가
- 기존 3개 식당의 카테고리·거리·가격 표시를 seed 데이터 기준으로 보정

### 8. `backend/scripts/seed-restaurants.ts` (신규 DB 시드 스크립트)
- **목적:** Supabase DB에 식당 18곳 + 메뉴 54건 삽입
- 프론트 seed와 동일한 UUID 규칙 사용
- `upsert` 방식이라 여러 번 실행해도 안전
- 실행 방법: `cd backend && npx ts-node scripts/seed-restaurants.ts`
- **실행 완료:** 2026-04-18 Supabase DB에 정상 삽입 확인

### UUID 규칙
```
식당: bbbbbbbb-0000-4000-8000-000000000NNN  (NNN = 001~018)
메뉴: cccccccc-0NNN-4000-8000-0000000000MM  (NNN = 식당번호, MM = 메뉴번호)
```

---

## 팀원에게 전달 필요한 수정 사항

### 메뉴 카테고리 탭 문제 — 김지효 담당

**현상:** 어떤 식당을 들어가든 카테고리 탭이 항상 `전체/추천/밥류/면류/분식/음료` 6개로 고정 표시됨. 맘스터치(양식), 아웃백(양식), 이디야(디저트) 등은 해당 카테고리가 없어서 '밥류'나 '음료'에 억지로 들어가는 상태.

**원인:** `lib/models/menu_item.dart`의 `MenuCategory` enum에 `western(양식)`, `dessert(디저트)` 값이 없음.

**수정 필요 파일:**
1. `lib/models/menu_item.dart` — `MenuCategory` enum에 `western('양식')`, `dessert('디저트')` 추가
2. `lib/features/menu/menu_screen.dart` — 해당 식당에 실제로 있는 카테고리만 탭으로 표시하도록 변경 (선택사항)

**수정 규모:** 10~20줄 수정, 간단한 작업

**장다연 쪽 임시 처리:** `menu_screen.dart`의 `_mapSeedCategory()`에서 `'양식' → rice`, `'디저트' → drink`로 매핑 중. 위 수정이 완료되면 이 매핑도 정확하게 변경 필요.

---

## 기존 구현 파일 수정 여부

| 대상 | 수정 여부 |
|---|---|
| lib/features/menu/menu_screen.dart | ✅ 식당별 메뉴 분리 표시 (seed 연결) |
| lib/features/home/home_screen.dart | ✅ AI 추천 식당 3개→5개 확장 |
| lib/features/* (그 외 화면) | ❌ 수정 안 함 |
| lib/providers/* | ❌ 수정 안 함 |
| lib/services/* | ❌ 수정 안 함 |
| lib/models/* | ❌ 수정 안 함 |
| lib/main.dart | ❌ 수정 안 함 |
| backend/src/* | ❌ 수정 안 함 |
| 설정 파일 (.env, pubspec 등) | ❌ 수정 안 함 |

---

## 파일 목록 전체

```
수정 (6):
  lib/data/seeds/restaurant_seeds.dart   ← ID를 UUID로 변경
  lib/data/seeds/menu_seeds.dart         ← ID를 UUID로 변경
  lib/core/utils/normalizer.dart
  lib/core/constants/ui_texts.dart
  lib/features/menu/menu_screen.dart     ← 식당별 메뉴 분리
  lib/features/home/home_screen.dart     ← 추천 식당 5개로 확장

신규 (7):
  lib/core/constants/condition_tag_map.dart
  lib/core/constants/home_recommendation_config.dart
  lib/core/constants/menu_display_config.dart
  lib/core/constants/recommendation_texts.dart
  lib/core/constants/recommendation_reason_categories.dart
  lib/core/constants/session_restaurant_config.dart
  backend/scripts/seed-restaurants.ts     ← DB 시드 스크립트

문서 (1):
  docs/week2_jdy_summary.md
```
