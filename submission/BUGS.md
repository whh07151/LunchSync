# LunchSync 디버깅 진척 현황 (2026-05-13)

이 파일은 다음 세션에서 바로 이어 디버깅하기 위한 시작점입니다.

## ✅ 현재 환경
- 폰: Galaxy S23 FE (`R5CX42N0YHF`) USB 디버깅 허용 완료
- adb: `C:\Users\whh07\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- 폰 자동 화면 꺼짐: 30분으로 늘려둠
- 설치된 APK: `app-release.apk` (EC2 백엔드 `https://lunchsync-api.duckdns.org/api` 연결)
- 패키지명: `com.example.capstone`

## 🔁 다음 시작 방법 (간단)
1. 폰 잠금 풀고 LunchSync 앱 켜기
2. PC에서 `adb devices` 로 폰 인식 확인
3. 사용자 보고한 4개 증상을 자동 조작 + 캡처로 차례로 재현

## 🐛 사용자가 보고한 증상 4개

### A. 식당 정보 안 나옴
- 현장 확인 결과: **사실 홈에는 AI 추천 식당이 표시됨** (강동호치킨, 황금식당 등)
- 사용자가 본 게 어떤 화면이었는지 재확인 필요 — 가능성: 식당 상세 페이지에서 데이터 없음

### B. AI 추천 식당 클릭해도 메뉴/정보 안 나옴
- 코드: 클릭 → `RestaurantDetailScreen` → `_loadDetail` + `_loadMenus` 둘 다 호출
- 의심: 추천 API가 반환한 `restaurantId` 가 DB의 실제 ID와 매칭 안 됨 (Gemini 가상 식당)
- 또는: `menus` 테이블에 그 식당의 메뉴 row가 없음
- 조치: 추천 카드 탭 후 화면 + logcat 의 API 응답 코드 확인 필요

### C. 점심세션 옆 지도 클릭해도 지도 안 나옴
- 코드: **홈 화면에 지도 위젯이 import 조차 안 됨** (`home_screen.dart` 의 주석: "📌 지도는 홈에 없음")
- 지도가 있는 곳: `RecommendationMapScreen` (CU-15) — AI 추천 리스트 → 우측 상단 지도 아이콘
- 사용자가 본 "지도" 가 어떤 버튼/아이콘이었는지 재확인 필요

### D. 팀원 설정 후 점심세션에 표시 안 됨
- 현장 확인: 홈의 "오늘의 세션" 비어있음 + 점심세션 탭도 "아직 비어있어요"
- 의심: `/api/sessions/today` 가 빈 응답 — EC2 DB의 sessions 테이블에 row 없거나, 본인 user_id로 매칭 안 됨
- 조치: Supabase 대시보드에서 sessions/session_members 테이블 row 확인 필요

## 📂 캡처된 폰 화면
`submission/screenshots/real-device/` 폴더에:
- `00-current-screen.png` 첫 진입 (개발자 옵션)
- `01-splash.png` 앱 실행 후
- `02-after-3s.png` 3초 후 (점심세션 탭)
- `step-01-home-tab.png` 검은 화면 (잠금)
- `step-01b-wakeup.png` 깨우기 후 점심세션 탭 (정상)
- `step-02-home.png` 검은 화면 (또 잠금)
- `step-02b-after-wake.png` 깨우기 후 **홈 탭 (AI 추천 식당 보임)** ← 진단 핵심
- `step-03-restaurant-detail.png` 검은 화면 (다시 잠금)
- `step-03b-recheck.png` 잠금화면

## 🔬 코드 정적 분석 결과 (이미 검토 완료)
1. `RestaurantsApiService.getRestaurants()` — lat/lng 안 보냄 (백엔드는 옵셔널이라 전체 반환)
2. `getRestaurantById/getMenus` — 응답 구조 코드 정상
3. `_onCardTap` (recommendation_list_screen) — 정상, 비교모드 아니면 식당 상세로 이동
4. `_goToFullMenu` (restaurant_detail_screen) — restaurantId 정상 전달
5. **결론**: 클라이언트 코드 자체에 버그 없음. **EC2 DB 데이터 또는 추천 API 응답이 핵심 원인**

## 🎯 다음 작업 순서 (재개 시)
1. **폰 잠금 풀고 앱 켜기**
2. **EC2 백엔드 데이터 상태 확인** (Supabase 대시보드)
   - `restaurants` 테이블 row 개수
   - `menu_items` 테이블 row 개수
   - `sessions` 테이블 row 개수 (오늘 날짜)
3. **adb 자동 조작으로 4개 증상 차례로 재현 + 캡처**
   - 홈 → AI 추천 카드 탭 → 식당 상세 → 메뉴 (B 증상)
   - 점심 만들기 → 세션 생성 → 홈으로 돌아와 표시 여부 (D 증상)
   - AI 추천 화면에서 우측 상단 지도 아이콘 탭 (C 증상)
4. **(선택) scrcpy 설치하면 미러링으로 더 편함**

---
_작성: 2026-05-13 17:03_
