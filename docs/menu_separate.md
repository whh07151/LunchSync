# [프롬프트] 식당별 메뉴 분리 — API 기반으로 재구현

> 이 파일 내용 전체를 Claude에게 붙여넣으면 됩니다.

---

## 목표

AI/크롤로 수집된 메뉴가 DB에 들어왔을 때, 식당마다 **해당 식당 전용 메뉴**만 뜨도록 `lib/features/menu/menu_screen.dart`를 정리해줘.

## 배경

- AI 또는 카카오 로컬 크롤이 식당의 메뉴·가격을 `menu_items` 테이블에 저장 (`restaurant_id` FK로 식당 연결)
- 백엔드 `GET /api/restaurants/:id/menus` → `{ success, data: { categories[], menus[] } }` 반환
- Flutter는 `RestaurantsApiService.getMenus(accessToken, restaurantId)`로 호출 (이미 구현됨, `lib/services/restaurants_api_service.dart`)

## 현재 상태 (이전 한 번 해둔 과도기 코드, 이걸 정리해야 함)

`menu_screen.dart`는 3단 폴백으로 동작 중:
1. `restaurantId`가 있으면 API 호출 → `_apiMenus`
2. 실패 시 로컬 `restaurantSeeds` + `menuSeeds`로 이름 매칭 필터링
3. 그것도 없으면 `_mockMenuItems` 12개 하드코딩

→ 1단계만 남기고 2·3단계를 지워야 함.

## 이전 dayeon 구조 (참고만, 그대로 포팅하지 말 것)

이전에 seed 배열을 직접 필터링할 때 쓰던 분리 로직의 개념:

```dart
// 이름으로 식당 찾기 → 해당 restaurantId로 메뉴 필터링
final matching = restaurantSeeds.where((r) => r.name == widget.restaurantName);
final items = menuSeeds.where((m) => m.restaurantId == matching.first.id).toList();
// 카테고리 문자열 → MenuCategory enum 변환
// rice / noodle / snack / drink (API), 밥류 / 면류 / 분식 / 음료 (한글) 둘 다 지원
```

이 **"restaurantId로 메뉴를 격리한다"** 개념만 가져오고, 실제 데이터 소스는 API로 교체해줘.

## 해야 할 일

1. `MenuScreen`의 `restaurantId` 파라미터를 **`required String`으로 변경** (nullable 제거)
2. `initState`에서 API 호출 → 단일 상태변수 `_menus`에 저장 (현재 `_apiMenus`, `_seedMenus`, `_mockMenuItems` 구조 제거)
3. 로딩 중: `CircularProgressIndicator` 중앙 배치
4. API가 빈 배열 반환: "메뉴 정보를 준비 중이에요" 빈 상태 UI
5. 카테고리 매핑 함수(`_mapApiCategory`)는 유지 — API `'rice'`·`'noodle'`·`'snack'`·`'drink'` → `MenuCategory` enum
6. 호출부 수정:
   - `lib/features/restaurant/restaurant_detail_screen.dart`의 `_goToFullMenu` — `restaurantId: widget.restaurantId` 이미 넘기고 있는지 확인
   - `lib/features/home/home_screen.dart` 및 기타 MenuScreen 사용처도 `restaurantId` 전달하도록 변경
7. 더 이상 쓰지 않는 파일 참조 삭제:
   - `import '../../data/seeds/restaurant_seeds.dart';`
   - `import '../../data/seeds/menu_seeds.dart';`
   - `_mockMenuItems` 상수 및 `_seedRestaurantId`, `_seedMenus` 전부

## 참고 파일

| 파일 | 역할 |
|---|---|
| `lib/features/menu/menu_screen.dart` | 수정 대상 |
| `lib/services/restaurants_api_service.dart` | `getMenus()` 호출 |
| `lib/models/menu_item.dart` | `MenuItem`, `MenuCategory` enum |
| `lib/features/restaurant/restaurant_detail_screen.dart` | MenuScreen 호출부 1 |
| `lib/features/home/home_screen.dart` | MenuScreen 호출부 2 (있으면) |
| `backend/src/restaurants/restaurants.service.ts` | 백엔드 응답 확인 |
| `docs/LUNCHSYNC_DTO.md` L476~ | 메뉴 API DTO 명세 |

## 검증

- `flutter analyze` → 0 issue
- 앱 실행 → 로그인 → 홈 → 식당 A 클릭 → "메뉴 전체 보기" → 식당 A 메뉴만 표시
- 뒤로가기 → 식당 B 클릭 → "메뉴 전체 보기" → 식당 B의 **다른** 메뉴 표시
- `lib/features/menu/menu_screen.dart`에 seed/Mock 관련 import·상수 남아있지 않은지 확인
cc