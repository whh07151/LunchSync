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

## 기존 구현 파일 수정 여부

| 대상 | 수정 여부 |
|---|---|
| lib/features/* (화면) | ❌ 수정 안 함 |
| lib/providers/* | ❌ 수정 안 함 |
| lib/services/* | ❌ 수정 안 함 |
| lib/models/* | ❌ 수정 안 함 |
| lib/main.dart | ❌ 수정 안 함 |
| backend/src/* | ❌ 수정 안 함 |
| 설정 파일 (.env, pubspec 등) | ❌ 수정 안 함 |

---

## 파일 목록 전체

```
수정 (4):
  lib/data/seeds/restaurant_seeds.dart
  lib/data/seeds/menu_seeds.dart
  lib/core/utils/normalizer.dart
  lib/core/constants/ui_texts.dart

신규 (6):
  lib/core/constants/condition_tag_map.dart
  lib/core/constants/home_recommendation_config.dart
  lib/core/constants/menu_display_config.dart
  lib/core/constants/recommendation_texts.dart
  lib/core/constants/recommendation_reason_categories.dart
  lib/core/constants/session_restaurant_config.dart

문서 (1):
  docs/week2_jdy_summary.md
```
