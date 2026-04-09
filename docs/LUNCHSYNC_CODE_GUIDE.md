# LunchSync 코드 가이드
**작성일:** 2026-04-08  
**대상:** 팀 전체 (특히 백엔드 담당자)  
**기준 코드:** Flutter 앱 + NestJS 백엔드 현재 구현 상태

---

## 목차

1. [프로젝트 전체 구조](#1-프로젝트-전체-구조)
2. [Flutter 앱 — 진입점 및 라우팅](#2-flutter-앱--진입점-및-라우팅)
3. [Flutter 앱 — 디자인 시스템](#3-flutter-앱--디자인-시스템)
4. [Flutter 앱 — 공용 위젯](#4-flutter-앱--공용-위젯)
5. [Flutter 앱 — 데이터 모델](#5-flutter-앱--데이터-모델)
6. [Flutter 앱 — 상태 관리 (Riverpod)](#6-flutter-앱--상태-관리-riverpod)
7. [Flutter 앱 — API 서비스](#7-flutter-앱--api-서비스)
8. [Flutter 앱 — 화면별 상세](#8-flutter-앱--화면별-상세)
9. [NestJS 백엔드 — 서버 진입점](#9-nestjs-백엔드--서버-진입점)
10. [NestJS 백엔드 — 인증 모듈](#10-nestjs-백엔드--인증-모듈)
11. [NestJS 백엔드 — 유저 모듈](#11-nestjs-백엔드--유저-모듈)
12. [NestJS 백엔드 — Supabase 연동](#12-nestjs-백엔드--supabase-연동)
13. [전체 데이터 흐름](#13-전체-데이터-흐름)
14. [현재 구현된 API 목록](#14-현재-구현된-api-목록)
15. [Mock 데이터 현황 및 교체 포인트](#15-mock-데이터-현황-및-교체-포인트)
16. [팀원 간 협업 포인트](#16-팀원-간-협업-포인트)
17. [배포 전 체크리스트](#17-배포-전-체크리스트)

---

## 1. 프로젝트 전체 구조

```
capstone/
├── lib/                          ← Flutter 앱 (손님앱)
│   ├── main.dart                 ← 진입점, 라우팅
│   ├── core/
│   │   ├── config/
│   │   │   └── app_config.dart   ← 카카오 앱 키, 백엔드 URL (gitignore)
│   │   ├── theme/                ← 색상, 여백, 폰트, 테마
│   │   ├── widgets/              ← 공용 위젯 (버튼, 카드, 입력창, 칩)
│   │   └── debug/
│   │       └── debug_toast.dart  ← 개발용 화면 ID 토스트
│   ├── models/
│   │   ├── member.dart           ← 멤버/친구 데이터 모델
│   │   └── menu_item.dart        ← 메뉴 항목 + 카테고리 enum
│   ├── providers/
│   │   ├── user_provider.dart    ← 로그인 유저 정보 + JWT 전역 상태
│   │   ├── session_provider.dart ← 세션 생성 흐름 전역 상태
│   │   └── cart_provider.dart    ← 장바구니 전역 상태
│   ├── services/
│   │   ├── kakao_auth_service.dart  ← 카카오 SDK 로그인/로그아웃
│   │   ├── auth_api_service.dart    ← POST /auth/kakao 호출
│   │   └── users_api_service.dart   ← GET/PATCH /users/me 호출
│   └── features/
│       ├── splash/               ← CU-01 스플래시
│       ├── auth/                 ← CU-02 카카오 로그인
│       ├── onboarding/           ← CU-03 프로필 설정, CU-05 조건 설정
│       ├── home/                 ← CU-06 홈 대시보드
│       ├── session/              ← CU-08 멤버 선택
│       ├── menu/                 ← CU-16 메뉴 목록/장바구니
│       ├── notifications/        ← CU-22 알림함
│       └── my_info/              ← CU-23 내정보/설정
│
└── backend/
    └── src/
        ├── main.ts               ← 서버 진입점, 글로벌 설정
        ├── app.module.ts         ← 루트 모듈
        ├── auth/                 ← 카카오 로그인 + JWT 발급
        ├── users/                ← 유저 프로필 조회/수정
        └── supabase/             ← Supabase 클라이언트 싱글턴
```

### 아키텍처 원칙

```
Flutter 앱
    ↕  HTTP API만 (Supabase 직접 접근 절대 금지)
NestJS 서버  [단일 문지기]
    - 권한 검증 (JWT)
    - 비즈니스 로직
    - 트랜잭션 처리
    ↕  SQL 쿼리 (service_role 키, RLS 우회)
Supabase PostgreSQL  [DB 전용]
```

> **Riverpod의 역할**: 백엔드 응답의 **프론트 세션 캐시**. Source of truth는 Supabase DB.

---

## 2. Flutter 앱 — 진입점 및 라우팅

### `lib/main.dart`

**역할**: 앱 시작점, 첫 화면 결정, 전체 네비게이션 흐름 관리

#### 클래스 구조

| 클래스 | 역할 |
|--------|------|
| `main()` | 카카오 SDK 초기화 + `ProviderScope` + `runApp` |
| `LunchSyncApp` | `MaterialApp` 설정 (테마, 첫 화면) |
| `_RootNavigator` | SharedPreferences 확인 후 첫 화면 결정 |
| `_PlaceholderScreen` | 미구현 화면 임시 대체 |

#### `_RootNavigator` 동작 흐름

```
앱 실행
    ↓
SharedPreferences 조회 ('onboarding_done')
    ↓
━━━━━━━━━━━━━━━━━━━━━━━━
false (첫 실행)     true (재실행)
━━━━━━━━━━━━━━━━━━━━━━━━
SplashScreen        LoginScreen (스플래시 건너뜀)
    ↓                    ↓
LoginScreen         isNewUser?
    ↓                ┌───┴───┐
isNewUser?          No      Yes
┌───┴───┐           ↓       ↓
No      Yes       Home   Onboarding
↓       ↓
Home  Onboarding (CU-03 → CU-05 → Home)
```

#### `_handleLoginSuccess()` 메서드
- `isNewUser == true` → `ProfileSetupScreen` → `ConditionSetupScreen` → `HomeScreen`
- `isNewUser == false` → `HomeScreen` 바로 이동

#### 로그아웃 후 네비게이션
- `userProvider.clear()` 호출
- `Navigator.pushAndRemoveUntil` 로 스택 전체 제거
- `LoginScreen`으로 이동 (온보딩 완료 기기이므로 스플래시 없이)

#### 의존성
- `kakao_flutter_sdk_user` — SDK 초기화
- `shared_preferences` — `onboarding_done` 플래그 저장
- `flutter_riverpod` — `ProviderScope`

---

## 3. Flutter 앱 — 디자인 시스템

### `lib/core/theme/app_colors.dart`

**역할**: 앱 전체 색상 정의 (손님앱/점주앱 분리)

| 색상 그룹 | 손님앱 | 점주앱 |
|-----------|--------|--------|
| primary | `#FF8C42` (주황) | `#1DBFA3` (청록) |
| primaryDark | `#E67A30` | `#189E88` |
| primaryLight | `#FFAD72` | `#4ECFBB` |
| primarySurface | `#FFF5F0` | `#F0FBF9` |

**공통 색상** (`AppColors`):
- 배경: `background: #FFFFFF`, `backgroundGrey: #F8F8F8`
- 텍스트: `textPrimary: #1A1A1A`, `textSecondary: #666666`, `textHint: #999999`
- 구분선: `divider: #EEEEEE`, `border: #DDDDDD`
- 상태: `success: #27AE60`, `error: #E74C3C`, `warning: #F39C12`

---

### `lib/core/theme/app_spacing.dart`

**역할**: 여백 및 모서리 둥글기 상수 (8px 그리드 시스템)

| 상수 | 값 | 용도 |
|------|----|------|
| `xs` | 4px | 아이콘-텍스트 간격 |
| `sm` | 8px | 관련 요소 간격 |
| `md` | 16px | 기본 간격 |
| `lg` | 24px | 섹션 구분 |
| `xl` | 32px | 큰 구분 |
| `screenHorizontal` | 20px | 화면 좌우 여백 |

| 둥글기 상수 | 값 | 용도 |
|-------------|----|----|
| `button` | 28px | 버튼 (알약 모양) |
| `card` | 12px | 카드 |
| `chip` | 20px | 칩/태그 |
| `input` | 10px | 입력 필드 |
| `bottomSheet` | 20px | 바텀시트 상단 |

---

### `lib/core/theme/app_text_styles.dart`

**역할**: 텍스트 스타일 정의 (Noto Sans 폰트, 한글 최적화)

| 스타일 | 크기 | 굵기 | 용도 |
|--------|------|------|------|
| `heading1` | 28px | w700 | 메인 타이틀 |
| `heading2` | 22px | w700 | 섹션 제목 |
| `heading3` | 18px | w600 | 앱바/카드 제목 |
| `bodyLarge` | 16px | w400 | 주요 본문 |
| `bodyMedium` | 14px | w400 | 일반 텍스트 |
| `bodySmall` | 12px | w400 | 부가 설명 (회색) |
| `buttonLarge` | 16px | w600 | 큰 버튼 |
| `buttonMedium` | 14px | w600 | 중간 버튼 |
| `caption` | 11px | w400 | 최소 텍스트 (연회색) |
| `label` | 12px | w500 | 탭/칩 레이블 |

---

### `lib/core/theme/app_theme.dart`

**역할**: 전체 `ThemeData` 생성

**사용법**:
```dart
// main.dart
theme: AppTheme.of(AppType.customer)  // 손님앱 테마
theme: AppTheme.of(AppType.owner)     // 점주앱 테마
```

**설정 항목**: ColorScheme, TextTheme, AppBarTheme, ElevatedButton, OutlinedButton, TextButton, InputDecoration, Card, BottomNavigationBar, Chip 스타일 전부 포함

---

## 4. Flutter 앱 — 공용 위젯

### `lib/core/widgets/app_button.dart`

| 위젯 | 역할 | 주요 파라미터 |
|------|------|--------------|
| `AppPrimaryButton` | 주요 CTA (배경 채워짐) | `label`, `onPressed`, `isLoading`, `isEnabled` |
| `AppOutlinedButton` | 보조 버튼 (테두리만) | `label`, `onPressed` |
| `AppTextButton` | 텍스트만 버튼 | `label`, `onPressed` |
| `AppIconButton` | 아이콘 + 텍스트 버튼 | `label`, `icon`, `onPressed` |
| `AppChip` | 선택 가능한 칩/태그 | `label`, `isSelected`, `onTap` |

**`AppChip` 사용 예** (온보딩 반경 선택):
```dart
AppChip(
  label: '500m',
  isSelected: _selectedRadius == '500m',
  onTap: () => setState(() => _selectedRadius = '500m'),
)
```

---

### `lib/core/widgets/app_card.dart`

| 위젯 | 특징 | 용도 |
|------|------|------|
| `AppCard` | 흰 배경 + 연한 테두리 | 일반 정보 카드 |
| `AppElevatedCard` | 그림자 있음 (elevation: 4) | 추천 식당, 강조 카드 |
| `AppHighlightCard` | primarySurface 배경 | AI 추천, 특별 강조 |

---

### `lib/core/widgets/app_text_field.dart`

**위젯**: `AppTextField`

**주요 파라미터**:
- `controller` — TextEditingController (필수)
- `label` — 입력창 위 레이블
- `hint` — 입력창 안 힌트 텍스트
- `errorText` — 빨간 오류 메시지
- `maxLength` — 최대 글자 수
- `obscureText` — 비밀번호 숨김
- `onChanged` — 입력값 변경 콜백

---

### `lib/core/widgets/app_bar.dart`

| 위젯 | 역할 |
|------|------|
| `AppCustomBar` | 일반 앱바 (제목, 뒤로가기, 액션 버튼) |
| `AppSearchBar` | 검색 전용 앱바 (실시간 검색어 감지) |

---

### `lib/core/debug/debug_toast.dart`

**역할**: 개발 중에만 화면 ID 표시 (릴리즈 빌드에서 자동 비활성화)

```dart
// 각 화면 initState에서 호출
DebugToast.show(context, 'CU-06');
```

> ⚠️ **배포 전 삭제 필요**: 모든 화면의 `DebugToast.show()` 호출 제거

---

## 5. Flutter 앱 — 데이터 모델

### `lib/models/member.dart`

**역할**: CU-08 멤버 선택 화면에서 사용하는 팀원 데이터 모델

```dart
class Member {
  final String id;           // 사용자 고유 식별자 (Supabase users.id)
  final String name;         // 표시 이름
  final String organization; // 소속 (팀명, 부서명)
}
```

**연결 파일**:
- `member_select_screen.dart` — UI에서 사용
- `session_provider.dart` — 선택 결과 전역 저장
- CU-09 (우현호 담당) — `sessionProvider.selectedMembers` 읽기

> **TODO**: CU-09 연동 시 `kakaoId`, `profileImageUrl` 필드 추가 가능

---

### `lib/models/menu_item.dart`

**역할**: 메뉴 화면 및 장바구니에서 사용하는 메뉴 항목 모델

```dart
enum MenuCategory { all, recommended, rice, noodle, snack, drink }

class MenuItem {
  final String id;           // 메뉴 고유 식별자
  final String restaurantId; // 소속 식당 ID (장다연 기준: Menu.restaurantId = Restaurant.id)
  final String name;         // 메뉴 이름
  final String description;  // 설명
  final int price;           // 가격 (원 단위)
  final MenuCategory category;
  final String? imageUrl;
  final bool isSoldOut;      // 품절 여부 (기본: false)

  // TODO: 장다연 씨 DB 컬럼 확정 후 추가 예정
  // final bool spicy;
  // final String? allergyNotes;

  String get formattedPrice  // "6,500원" 형태 반환
}
```

**연결 파일**:
- `menu_screen.dart` — 목록 표시
- `cart_provider.dart` — 장바구니 상태

> **API 연동 시**: `GET /restaurants/{id}/menus` 응답으로 Mock 교체

---

## 6. Flutter 앱 — 상태 관리 (Riverpod)

### `lib/providers/user_provider.dart`

**역할**: 로그인 유저 정보 + JWT를 앱 전역에서 관리

```dart
class UserState {
  final String? accessToken;  // LunchSync JWT (모든 API 요청 헤더에 포함)
  final String? userId;       // Supabase users.id (UUID)
  final String? name;         // 표시 이름
  final String? org;          // 소속
  final String? profileImage; // 프로필 이미지 URL

  bool get isLoggedIn => accessToken != null;
}
```

**UserNotifier 메서드**:

| 메서드 | 호출 시점 | 역할 |
|--------|----------|------|
| `setUser(AuthResponse)` | 로그인 완료 직후 | JWT + 기본 유저 정보 저장 |
| `setFromProfile(UserProfile)` | GET /users/me 완료 후 | DB 최신값으로 갱신 (name, org, profileImage) |
| `clear()` | 로그아웃 시 | 모든 상태 초기화 |

**사용법**:
```dart
// 상태 읽기 (UI 자동 반영)
ref.watch(userProvider).name
ref.watch(userProvider).accessToken

// API 요청 헤더에 포함
final token = ref.read(userProvider).accessToken;
headers: {'Authorization': 'Bearer $token'}

// 로그인 후 저장
ref.read(userProvider.notifier).setUser(authResponse);

// 로그아웃 시
ref.read(userProvider.notifier).clear();
```

> **저장 범위**: 인메모리 (앱 종료 시 초기화 → 재실행 시 재로그인 필요)

---

### `lib/providers/session_provider.dart`

**역할**: CU-08 → CU-09 멤버 데이터 전달

```dart
class SessionState {
  final List<Member> selectedMembers;
}
```

**데이터 흐름**:
```
CU-08 MemberSelectScreen
  → sessionProvider.notifier.setSelectedMembers(members)
      ↓
CU-09 (우현호 담당)
  → ref.watch(sessionProvider).selectedMembers 로 읽기
```

---

### `lib/providers/cart_provider.dart`

**역할**: 메뉴 화면에서 선택한 장바구니 전역 상태

```dart
class CartItem {
  final MenuItem item;
  final int quantity;
  int get subtotal => item.price * quantity;
}

class CartNotifier extends Notifier<List<CartItem>> {
  void addItem(MenuItem)          // 담기 (이미 있으면 수량 +1)
  void decreaseItem(String id)    // 수량 -1 (0이면 제거)
  void removeItem(String id)      // 항목 제거
  void clear()                    // 전체 비우기
  int quantityOf(String id)       // 특정 메뉴 현재 수량
  int get totalPrice              // 총 금액
  int get totalCount              // 총 수량
}
```

**데이터 흐름**:
```
CU-16 MenuScreen
  → cartProvider.addItem() / decreaseItem() / removeItem()
      ↓
CU-20 (안태환 담당) — 장바구니 내용 확인
      ↓
CU-21 결제 완료 후 → cartProvider.clear()
```

> **현재**: Riverpod 인메모리 저장 (앱 종료 시 소멸)  
> **목표**: 서버 사이드 장바구니 전환 예정 (POST/PATCH/DELETE /cart)

---

## 7. Flutter 앱 — API 서비스

### `lib/services/kakao_auth_service.dart`

**역할**: 카카오 SDK 로그인/로그아웃 처리

**`login()` 흐름**:
```
카카오톡 설치 여부 확인
    ├── 있음 → 카카오톡 앱 로그인 시도
    │           실패 시 → 웹 로그인 fallback
    └── 없음 → 카카오 웹 로그인
              ↓
          access token 반환
```

**반환**: `KakaoLoginResult`
- `isSuccess: bool`
- `kakaoAccessToken: String?`
- `errorMessage: String?`

---

### `lib/services/auth_api_service.dart`

**역할**: LunchSync 백엔드 인증 API 호출

**`loginWithKakao(String kakaoAccessToken)`**
- 엔드포인트: `POST /api/auth/kakao`
- 요청: `{ "kakaoAccessToken": "..." }`
- 응답 파싱 → `AuthResponse` 반환

```dart
class AuthResponse {
  final String accessToken;   // LunchSync JWT
  final bool isNewUser;       // true: 온보딩 필요 / false: 홈으로 바로
  final String userId;        // Supabase users.id (UUID)
  final String name;          // 카카오 닉네임
  final String? profileImage;
}
```

---

### `lib/services/users_api_service.dart`

**역할**: 유저 프로필 조회/수정 API 호출

#### `getMe(String accessToken)` → `UserProfile?`
- 엔드포인트: `GET /api/users/me`
- 헤더: `Authorization: Bearer {token}`
- 사용처: `HomeScreen.initState()`, `MyInfoScreen.initState()`

#### `updateMe({accessToken, name?, org?, radius?, budget?, speed?})` → `bool`
- 엔드포인트: `PATCH /api/users/me`
- 사용처: 온보딩 완료 시 (`condition_setup_screen.dart`)

```dart
class UserProfile {
  final String id;
  final String name;
  final String? org;
  final String? profileImage;
  final String? radius;   // "500m", "1km" 등
  final int? budget;      // 원 단위 (예: 10000)
  final String? speed;    // "FAST", "NORMAL", "SLOW"
  final String? role;     // "CUSTOMER", "OWNER"
}
```

---

## 8. Flutter 앱 — 화면별 상세

### CU-01 `lib/features/splash/splash_screen.dart`

**완료 기준**: 탭 1회로 로그인 화면 진입 + 재실행 시 스플래시 건너뜀

| 요소 | 내용 |
|------|------|
| 로고 | 주황 원형 (임시 아이콘, 실제 로고로 교체 필요) |
| 버튼 1 | "카카오로 시작하기" → `onStart()` 콜백 |
| 버튼 2 | "서비스 둘러보기" → `onBrowse()` 콜백 (미구현) |
| 권한 안내 | 위치, 알림 |

**`markOnboardingDone()`**: SharedPreferences에 `onboarding_done = true` 저장
- 호출 위치: `condition_setup_screen.dart → _handleComplete()` 내부

---

### CU-02 `lib/features/auth/login_screen.dart`

**완료 기준**: 카카오 인증 후 신규/기존 분기

**동작 흐름**:
```
버튼 탭
    → KakaoAuthService.login()         (카카오 SDK)
    → AuthApiService.loginWithKakao()  (백엔드 API)
    → userProvider.setUser()           (전역 상태 저장)
    → onLoginSuccess(isNewUser)        (화면 분기)
```

**에러 처리**: 카카오 실패/서버 실패 모두 스낵바로 표시

---

### CU-03 `lib/features/onboarding/profile_setup_screen.dart`

**완료 기준**: 이름/소속/반경 입력 → 다음 화면 이동

| 입력 | 유효성 조건 |
|------|------------|
| 이름 | 필수 (1자 이상) |
| 소속 | 필수 (1자 이상) |
| 반경 | 칩 선택 (기본값 500m) |

**"다음" 활성화 조건**: 이름 + 소속 모두 입력 시

> **⚠️ 설계 차이**: 명세서는 이 화면에서 `POST /users` 호출을 요구하나,  
> 현재는 입력값을 메모리에만 보관하고 **CU-05에서 `PATCH /users/me`로 한 번에 전송**.  
> 이는 워킹 스켈레톤 단계의 의도적 간소화. 실서비스 전환 시 수정 필요.

---

### CU-05 `lib/features/onboarding/condition_setup_screen.dart`

**완료 기준**: 반경/예산/속도 저장 후 홈 진입

| 설정 항목 | 방식 | 기본값 |
|----------|------|--------|
| 반경 | 슬라이더 (500m~3km) | 1000m |
| 예산 | 칩 선택 5단계 | 1만원 이하 |
| 식사 속도 | 칩 선택 3단계 | NORMAL |

**예산 칩 → DB 정수 변환** (`_budgetToInt()`):

| 칩 레이블 | DB 저장값 |
|----------|----------|
| 5천원 이하 | 5000 |
| 8천원 이하 | 8000 |
| 1만원 이하 | 10000 |
| 1만5천원 이하 | 15000 |
| 제한 없음 | null |

**속도 API 값**: `FAST`, `NORMAL`, `SLOW`

**`_handleComplete()` 순서**:
1. `PATCH /api/users/me` — name, org, radius, budget, speed 저장
2. `markOnboardingDone()` — SharedPreferences 플래그 저장
3. `widget.onComplete()` — HomeScreen으로 이동

---

### CU-06 `lib/features/home/home_screen.dart`

**완료 기준**: 주요 플로우 3개 이상 접근 가능 + 실제 유저 데이터 표시

**CTA 버튼 연결 현황**:

| 버튼 | 연결 화면 | 상태 |
|------|----------|------|
| 점심 만들기 | CU-08 MemberSelectScreen | ✅ |
| 친구 초대 | CU-08 MemberSelectScreen | ✅ |
| 최근 이력 | 내역 탭 (index: 3) | ✅ |
| 알림 | CU-22 NotificationScreen | ✅ |

**하단 탭 연결 현황**:

| 탭 | 화면 | 상태 |
|----|------|------|
| 0 홈 | HomeScreen 자신 | ✅ |
| 1 점심세션 | Placeholder | ⏳ CU-09 대기 |
| 2 주문현황 | Placeholder | ⏳ CU-20 대기 |
| 3 내역 | Placeholder | ⏳ 미구현 |
| 4 내정보 | MyInfoScreen | ✅ |

**`_loadUserProfile()`**: 화면 진입 시 `GET /users/me` 호출 → `userProvider.setFromProfile()` → 이름/소속 최신화

**Mock 데이터** (API 연동 대기):
- `_mockSession` — 오늘의 세션 (GET /sessions/today로 교체 예정)
- `_mockRestaurants` — AI 추천 식당 (GET /restaurants로 교체 예정)

---

### CU-08 `lib/features/session/member_select_screen.dart`

**완료 기준**: 멤버 선택 후 sessionProvider에 저장

**구성 요소**:
- 검색창 (이름/소속 필터링)
- 친구 목록 (프로필 아바타 + 이름 + 소속 + 체크박스)
- 선택 인원 수 표시
- "조건 설정하기" 버튼

**Mock 친구 목록** 8명 (API 연동 전 임시):
> 안태환(개발팀), 장다현(디자인팀), 우현호(기획팀), 최예은(개발팀),  
> 정우진(마케팅팀), 한지수(개발팀), 오태양(기획팀), 신예린(디자인팀)

**"조건 설정하기" 동작**:
```dart
ref.read(sessionProvider.notifier).setSelectedMembers(selectedMembers);
widget.onNext(selectedMembers);
// TODO: 우현호 CU-09 완성 후 → CU-09로 이동하도록 교체
```

> **API 연동 시**: `_mockFriends` → `GET /users` 또는 카카오 친구 API로 교체

---

### CU-16 `lib/features/menu/menu_screen.dart`

**완료 기준**: 카테고리별 메뉴 탐색 + 장바구니 추가/수정/제거 가능

**카테고리 탭**: 전체 / 추천 / 밥류 / 면류 / 분식 / 음료

**장바구니 조작**:

| 동작 | 코드 |
|------|------|
| 담기 | `cartProvider.notifier.addItem(item)` |
| 수량 증가 | `cartProvider.notifier.addItem(item)` |
| 수량 감소 | `cartProvider.notifier.decreaseItem(id)` |
| 삭제 | `cartProvider.notifier.removeItem(id)` |

**하단 고정 바**: 총 수량 + 총 금액 + "주문하기" 버튼

**파라미터**: `restaurantName: String` (앱바 제목으로 표시)

> **API 연동 시**: `_mockMenuItems` → `GET /restaurants/{id}/menus`로 교체  
> `restaurantName` → `restaurantId`도 추가로 전달 필요

---

### CU-22 `lib/features/notifications/notification_screen.dart`

**완료 기준**: 알림 4종 이상 확인 가능

**알림 타입** (`NotificationType`):

| 타입 | 설명 |
|------|------|
| `ORDER_RECEIVED` | 점주에게 새 주문 알림 |
| `ORDER_ACCEPTED` | 주문 수락됨 |
| `ORDER_DONE` | 조리 완료, 수령 요청 |
| `VOTE_RESULT` | 투표 결과 확정 |

**UI 기능**:
- 알림 탭 → 읽음 처리
- "전체 읽음" 버튼 → 모두 읽음 처리
- 읽지 않은 알림: 왼쪽 파란 점 + 배경 강조

> **API 연동 시**:
> - Mock → `GET /api/notifications`
> - 읽음 → `PATCH /api/notifications/:id/read`

---

### CU-23 `lib/features/my_info/my_info_screen.dart`

**완료 기준**: 온보딩 데이터 재수정 가능 + 실제 DB 연동

**화면 진입 시 데이터 로딩**:
```
initState()
    → _loadProfile()
    → GET /api/users/me
    → 컨트롤러/칩 상태 초기화
    → _originalXxx 저장 (취소 시 복구용)
```

**편집 모드** (`_isEditing: bool`):
- `false`: 읽기 전용 표시
- `true`: 텍스트 필드 + 칩 활성화

**"저장" 동작**:
```
PATCH /api/users/me
    ↓ 성공 시
_originalXxx 업데이트 (새 원본값으로)
userProvider.setFromProfile() (홈 화면 인사말도 즉시 반영)
```

**"취소" 동작**: `_originalXxx`로 모든 컨트롤러/상태 복원

**로그아웃**:
```
확인 다이얼로그 → 확인
    → userProvider.clear()
    → Navigator.pushAndRemoveUntil → LoginScreen
```

---

## 9. NestJS 백엔드 — 서버 진입점

### `backend/src/main.ts`

**역할**: NestJS 서버 글로벌 설정 및 시작

**설정 항목**:

| 항목 | 설정값 | 설명 |
|------|--------|------|
| ValidationPipe | `whitelist: true` | DTO에 없는 필드 자동 제거 |
| ValidationPipe | `forbidNonWhitelisted: true` | 정의 외 필드 시 400 에러 |
| ValidationPipe | `transform: true` | string → number 자동 변환 |
| CORS | `origin: '*'` | 모든 출처 허용 (개발 중) |
| Global Prefix | `/api` | 모든 엔드포인트에 /api 접두사 |
| PORT | `3000` | 환경변수로 변경 가능 |

> **⚠️ 배포 전**: `origin: '*'` → 실제 도메인으로 제한

---

### `backend/src/app.module.ts`

**역할**: 루트 모듈 — 모든 서브 모듈 통합

**현재 등록된 모듈**:

| 모듈 | 역할 |
|------|------|
| `ConfigModule` | `.env` 파일 읽기 (isGlobal: true) |
| `SupabaseModule` | Supabase 클라이언트 (@Global) |
| `AuthModule` | 카카오 로그인 + JWT 발급 |
| `UsersModule` | 유저 프로필 조회/수정 |

**향후 추가 예정** (담당자):

| 모듈 | 담당 |
|------|------|
| `SessionsModule` | 우현호 |
| `RestaurantsModule` | 안태환/장다연 |
| `MenusModule` | 안태환 |
| `VotesModule` | 우현호 |
| `CartModule` | 안태환 |
| `OrdersModule` | 우현호 |
| `NotificationsModule` | 미정 |

---

## 10. NestJS 백엔드 — 인증 모듈

### `backend/src/auth/auth.service.ts`

**역할**: 카카오 로그인 핵심 비즈니스 로직

**`kakaoLogin(token)` 전체 흐름**:
```
1. getKakaoUserInfo(token)
   → GET https://kapi.kakao.com/v2/user/me
   → kakao_id (Long), nickname (String), profile_image_url (String?) 획득

2. Supabase: SELECT * FROM users WHERE kakao_id = ?
   ├── 기존 유저 → isNewUser = false
   └── 신규 유저 → INSERT INTO users (kakao_id, name, profile_image, role='CUSTOMER', radius='500m')
                   isNewUser = true

3. JwtService.sign({ sub: userId })
   → JWT 발급 (만료: 7일)

4. AuthResult 반환
```

**`AuthResult` 인터페이스**:
```typescript
{
  accessToken: string;    // LunchSync JWT
  isNewUser: boolean;     // Flutter 화면 분기에 사용
  user: {
    id: string;           // Supabase users.id (UUID)
    name: string;         // 카카오 닉네임
    profileImage: string | null;
    role: string;         // "CUSTOMER" (손님앱 로그인 시 항상)
  };
}
```

---

### `backend/src/auth/auth.controller.ts`

**엔드포인트**: `POST /api/auth/kakao`

**요청**:
```json
{
  "kakaoAccessToken": "카카오_액세스_토큰"
}
```

**성공 응답** (200):
```json
{
  "success": true,
  "data": {
    "accessToken": "eyJhbGciOi...",
    "isNewUser": true,
    "user": {
      "id": "uuid-v4",
      "name": "홍길동",
      "profileImage": "https://k.kakaocdn.net/...",
      "role": "CUSTOMER"
    }
  }
}
```

**실패 응답** (401):
```json
{
  "statusCode": 401,
  "message": "유효하지 않은 카카오 토큰입니다."
}
```

---

### `backend/src/auth/jwt.strategy.ts`

**역할**: JWT 검증 전략 (Passport)

**추출 방식**: `Authorization: Bearer {token}` 헤더에서 추출

**`validate()` 반환값**:
```typescript
{ userId: payload.sub }  // req.user에 주입됨
```

**사용 예**:
```typescript
@UseGuards(JwtAuthGuard)
getMe(@Req() req: { user: { userId: string } }) {
  return this.usersService.getMe(req.user.userId);
}
```

---

### `backend/src/auth/jwt-auth.guard.ts`

**역할**: `@UseGuards(JwtAuthGuard)` 데코레이터로 엔드포인트 보호

- 유효한 JWT → `req.user = { userId }` 주입 후 통과
- 없거나 만료된 JWT → `401 Unauthorized` 반환

---

## 11. NestJS 백엔드 — 유저 모듈

### `backend/src/users/users.service.ts`

#### `getMe(userId: string)`

**역할**: JWT에서 추출한 userId로 내 프로필 조회

**Supabase 쿼리**:
```sql
SELECT id, name, org, profile_image, radius, budget, speed, role
FROM users
WHERE id = userId
```

**반환** (camelCase 변환됨):
```typescript
{
  id: string;
  name: string;
  org?: string;
  profileImage?: string;
  radius?: string;     // "500m", "1km", "2km" 등
  budget?: number;     // 원 단위 정수
  speed?: string;      // "FAST", "NORMAL", "SLOW"
  role?: string;       // "CUSTOMER", "OWNER"
}
```

**에러**: 유저 없으면 `NotFoundException` (404)

---

#### `updateMe(userId, UpdateUserDto)`

**역할**: 온보딩/내정보 수정 시 프로필 업데이트

**UpdateUserDto** (모든 필드 선택):
```typescript
{
  name?: string;
  org?: string;
  profileImage?: string;
  radius?: string;
  budget?: number;
  speed?: string;
}
```

**Supabase 쿼리**:
```sql
UPDATE users
SET name=?, org=?, profile_image=?, radius=?, budget=?, speed=?
WHERE id = userId
RETURNING id, name, org, profile_image, radius, budget, speed
```

> **변환**: 요청 camelCase → Supabase snake_case → 응답 camelCase

---

### `backend/src/users/users.controller.ts`

**엔드포인트**: `GET /api/users/me`

**요청 헤더**: `Authorization: Bearer {JWT}`

**성공 응답** (200):
```json
{
  "success": true,
  "data": {
    "id": "uuid-v4",
    "name": "홍길동",
    "org": "개발팀",
    "profileImage": "https://...",
    "radius": "1km",
    "budget": 10000,
    "speed": "NORMAL",
    "role": "CUSTOMER"
  }
}
```

---

**엔드포인트**: `PATCH /api/users/me`

**요청 헤더**: `Authorization: Bearer {JWT}`

**요청 바디** (수정할 필드만 포함):
```json
{
  "name": "홍길동",
  "org": "개발팀",
  "radius": "1km",
  "budget": 10000,
  "speed": "NORMAL"
}
```

**성공 응답** (200):
```json
{
  "success": true,
  "data": {
    "id": "uuid-v4",
    "name": "홍길동",
    "org": "개발팀",
    "radius": "1km",
    "budget": 10000,
    "speed": "NORMAL"
  }
}
```

---

## 12. NestJS 백엔드 — Supabase 연동

### `backend/src/supabase/supabase.service.ts`

**역할**: Supabase 클라이언트 싱글턴

**설정**:
- `SUPABASE_URL` — `.env`에서 읽음
- `SUPABASE_SERVICE_ROLE_KEY` — `.env`에서 읽음 (**서버 전용**, RLS 우회)

**사용법** (모든 서비스에서):
```typescript
constructor(private readonly supabase: SupabaseService) {}

// 조회
const { data, error } = await this.supabase.client
  .from('users')
  .select('id, name, ...')
  .eq('id', userId)
  .single();

// 삽입
const { data, error } = await this.supabase.client
  .from('users')
  .insert({ kakao_id, name, ... })
  .select()
  .single();
```

> **⚠️ 보안**: `service_role` 키는 절대 Flutter 앱에 노출 금지.  
> Flutter는 Supabase에 직접 접근하지 않음.

---

## 13. 전체 데이터 흐름

### 흐름 1: 카카오 로그인

```
Flutter                              NestJS                    Supabase
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[로그인 버튼 탭]
KakaoAuthService.login()
카카오 SDK → access token 획득
            ↓
POST /api/auth/kakao
{kakaoAccessToken}
                     ↓
                     kakaoUserInfo 조회
                     (카카오 API 호출)
                             ↓
                             SELECT FROM users
                             WHERE kakao_id = ?
                             ├── 기존: isNewUser=false
                             └── 신규: INSERT users
                                       isNewUser=true
                             ↓
                     JWT 발급 (7일)
                     ↓
            {accessToken, isNewUser, user}
            ↓
userProvider.setUser(response)
            ↓
isNewUser=true  → CU-03 → CU-05 → Home
isNewUser=false → Home
```

---

### 흐름 2: 온보딩 프로필 저장

```
Flutter                              NestJS              Supabase
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CU-03: 이름, 소속 입력 (메모리 보관)
CU-05: 반경, 예산, 속도 선택
[홈으로 이동] 탭
            ↓
PATCH /api/users/me
{name, org, radius, budget, speed}
Authorization: Bearer {JWT}
                     ↓
                     users.updateMe()
                     UPDATE users WHERE id=userId
                     ↓
            {수정된 프로필}
            ↓
markOnboardingDone() → SharedPreferences
HomeScreen 이동
```

---

### 흐름 3: 홈 진입 시 프로필 로딩

```
Flutter                         NestJS                Supabase
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HomeScreen.initState()
_loadUserProfile()
            ↓
GET /api/users/me
Authorization: Bearer {JWT}
                    ↓
                    users.getMe()
                    SELECT FROM users WHERE id=userId
                    ↓
            {name, org, ...}
            ↓
userProvider.setFromProfile()
인사말 헤더 갱신: "안녕하세요, {name}님!"
소속: "{org} · 오늘 점심은 어디로?"
```

---

### 흐름 4: 멤버 선택 → 세션 생성 (구현 예정)

```
Flutter                              Riverpod         NestJS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CU-08: 멤버 선택
sessionProvider
.setSelectedMembers(members)
                         ↓
                         sessionProvider
                         (selectedMembers 저장)
CU-09 (우현호 담당)
ref.watch(sessionProvider)
.selectedMembers 읽기
            ↓
POST /api/sessions ⏳
{memberIds, name, scheduledAt}
                              ↓
                              세션 생성 + 멤버 추가 트랜잭션
                              INSERT sessions
                              INSERT session_members (멤버 + 방장)
```

---

## 14. 현재 구현된 API 목록

### ✅ 구현 완료

| Method | 경로 | 인증 | 역할 |
|--------|------|------|------|
| `POST` | `/api/auth/kakao` | 없음 | 카카오 로그인 + JWT 발급 |
| `GET` | `/api/users/me` | JWT | 내 프로필 조회 |
| `PATCH` | `/api/users/me` | JWT | 프로필/조건 수정 |

### ⏳ 구현 예정

| Method | 경로 | 역할 | 담당 |
|--------|------|------|------|
| `POST` | `/api/sessions` | 세션 생성 | 우현호 |
| `GET` | `/api/sessions/today` | 오늘 세션 조회 | 우현호 |
| `GET` | `/api/sessions/:id/members` | 세션 멤버 목록 | 안태환 |
| `PATCH` | `/api/sessions/:id/status` | 세션 상태 변경 | 안태환 |
| `GET` | `/api/restaurants` | 식당 목록 (조건 필터) | 장다연/안태환 |
| `GET` | `/api/restaurants/:id` | 식당 상세 | 장다연 |
| `GET` | `/api/restaurants/:id/menus` | 메뉴 목록 | 안태환 |
| `POST` | `/api/votes` | 투표 | 우현호 |
| `GET` | `/api/sessions/:id/votes` | 투표 현황 | 안태환 |
| `POST` | `/api/cart` | 메뉴 담기 | 안태환 |
| `GET` | `/api/cart/:sessionId` | 장바구니 조회 | 안태환 |
| `PATCH` | `/api/cart/:id` | 수량 수정 | 안태환 |
| `DELETE` | `/api/cart/:id` | 항목 삭제 | 안태환 |
| `POST` | `/api/orders` | 주문 생성 | 우현호 |
| `GET` | `/api/orders/:id` | 주문 상태 조회 | 안태환 |
| `GET` | `/api/orders/today` | 오늘 주문 목록 (점주) | 안태환 |
| `PATCH` | `/api/orders/:id/status` | 주문 상태 변경 | 안태환 |
| `GET` | `/api/notifications` | 알림 목록 | 미정 |
| `PATCH` | `/api/notifications/:id/read` | 읽음 처리 | 미정 |

---

## 15. Mock 데이터 현황 및 교체 포인트

| 화면 | 파일 | Mock 변수 | 교체 대상 API |
|------|------|----------|--------------|
| CU-06 홈 | `home_screen.dart` | `_mockSession` | `GET /api/sessions/today` |
| CU-06 홈 | `home_screen.dart` | `_mockRestaurants` | `GET /api/restaurants` |
| CU-08 멤버 | `member_select_screen.dart` | `_mockFriends` | `GET /api/users` |
| CU-16 메뉴 | `menu_screen.dart` | `_mockMenuItems` | `GET /api/restaurants/:id/menus` |
| CU-22 알림 | `notification_screen.dart` | `_mockNotifications` | `GET /api/notifications` |

**교체 방법**: 각 파일의 `TODO: API 연동 시` 주석 위치에서 API 호출 코드로 교체

---

## 16. 팀원 간 협업 포인트

### Flutter → 백엔드 인터페이스 (김지효 ↔ 안태환/우현호)

#### 1. 세션 생성 (CU-08 → CU-09)

Flutter에서 `sessionProvider`에 저장된 멤버 목록:
```dart
// session_provider.dart
List<Member> selectedMembers  // id, name, organization
```
백엔드 `POST /api/sessions` 요청 시 `memberIds` 배열로 변환 필요.

---

#### 2. 메뉴 화면 진입 파라미터 (CU-13 → CU-16)

현재 `MenuScreen`은 `restaurantName: String`만 받음.  
실제 API 연동 시 `restaurantId: String` 추가 전달 필요:
```dart
// 현재
MenuScreen(restaurantName: '한솥도시락')

// API 연동 후
MenuScreen(restaurantName: '한솥도시락', restaurantId: 'uuid-v4')
```

---

#### 3. 장바구니 → 주문 (CU-16 → CU-19)

Flutter `cartProvider`에서 주문 시 필요한 데이터:
```dart
cartProvider.state          // List<CartItem>
cartProvider.notifier.totalPrice  // 총 금액
```
백엔드 `POST /api/orders` 요청 시 `sessionId`, `restaurantId`, `items`, `totalPrice` 필요.

---

#### 4. 알림 연동 (NotificationScreen)

Flutter에서 기대하는 `GET /api/notifications` 응답 구조:
```json
{
  "success": true,
  "data": {
    "unreadCount": 2,
    "notifications": [
      {
        "id": "uuid",
        "type": "ORDER_ACCEPTED",
        "title": "주문이 수락되었습니다",
        "message": "한솥도시락에서 주문을 수락했습니다.",
        "isRead": false,
        "createdAtLabel": "방금 전"
      }
    ]
  }
}
```
`type` 값: `ORDER_RECEIVED`, `ORDER_ACCEPTED`, `ORDER_DONE`, `VOTE_RESULT`

---

#### 5. 공통 응답 구조

모든 API는 다음 형식으로 통일:
```json
// 성공
{ "success": true, "data": { ... } }

// 실패
{ "success": false, "error": { "code": "...", "message": "..." } }
```

---

### 장다연 씨 → Flutter 인터페이스

#### MenuItem 필드 기준

```dart
// 현재 구현된 필드 (menu_item.dart)
class MenuItem {
  final String id;
  final String restaurantId;  // 장다연 기준: Menu.restaurantId = Restaurant.id
  final String name;
  final String description;
  final int price;
  final MenuCategory category;
  final String? imageUrl;
  final bool isSoldOut;
  // TODO: 장다연 씨 확정 후 추가
  // final bool spicy;
  // final String? allergyNotes;
}
```

`GET /restaurants/:id/menus` 응답의 각 메뉴 항목이 위 필드와 매핑되어야 합니다.

---

## 17. 배포 전 체크리스트

### Flutter 앱

- [ ] `DebugToast.show()` 호출 모든 화면에서 제거
- [ ] `app_config.dart`의 `backendBaseUrl` 실제 서버 URL로 변경
- [ ] Mock 데이터 → 실제 API 연동으로 교체 (위 표 참조)
- [ ] JWT 영구 저장 구현 (현재 인메모리 → `flutter_secure_storage` 검토)
- [ ] `print()` 디버그 로그 제거 (`auth_api_service.dart` 등)
- [ ] 카카오 `logout()` 실제 연결 (`kakao_auth_service.dart`)
- [ ] 프로필 사진 선택 기능 구현 (`profile_setup_screen.dart`)
- [ ] 에러 UI 완성 (네트워크 오류, 서버 오류 등)

### NestJS 백엔드

- [ ] `origin: '*'` → 실제 도메인으로 제한 (`main.ts`)
- [ ] `JWT_SECRET` 강력한 랜덤값으로 교체 (`.env`)
- [ ] 에러 응답 포맷 통일 (DTO 명세서 기준)
- [ ] 배포 전 `console.log` 및 디버그 코드 제거
- [ ] 환경변수 `.env` 파일 절대 커밋 금지 확인
- [ ] HTTPS 강제 설정
- [ ] Rate Limiting 적용 (인증 엔드포인트)
- [ ] Supabase `service_role` 키 재발급 (세션 중 노출 가능성)

---

*이 문서는 2026-04-08 기준 구현 상태를 반영합니다.*  
*코드 변경 시 해당 섹션을 업데이트해 주세요.*
