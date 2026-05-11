# LunchSync 회원가입·인증·역할분리 설계서

> 결정일: 2026-05-07
> 결정자: 우현호 (백엔드)
> 상태: 확정 — 명세서의 Q6(앱 분리 구조 미결) 항목 종결
> 적용 범위: 백엔드 NestJS, Flutter 프론트, Supabase DB

---

## 1. 배경

기존 명세서(v1.1, 2026-04-08)에는 손님앱/점주앱을 별도 Flutter 프로젝트로 만들지, 같은 앱에서 role로 분기할지가 미결(Q6) 상태였습니다.
또한 인증 방식이 카카오 OAuth 단독으로 한정되어 있어, 이메일/휴대폰 가입자를 받을 수 없었습니다.

본 문서는 위 두 미결 사항을 한 번에 정리하여 **단일 앱 + 다중 인증 + OWNER 승인제** 구조로 확정합니다.
캡스톤 제출이 1차 목표이므로 운영 비용을 0원으로 유지하면서도 모든 인증 시나리오를 시연 가능한 형태로 설계했습니다.

---

## 2. 핵심 의사결정

### 2.1 단일 앱 + role 분기 (Q6 결정)

| 항목 | 결정 |
|---|---|
| 앱 분리 여부 | **단일 Flutter 앱**으로 통합 |
| 화면 분기 기준 | `users.role` 값 (`CUSTOMER` / `OWNER`) |
| 테마 분기 | `AppType.customer` (주황) / `AppType.owner` (청록) — 이미 `lib/core/theme/`에 준비됨 |
| 진입 흐름 | 로그인 성공 → user role 조회 → 손님 화면 또는 사장 화면 |

`lib/main.dart`의 `AppTheme.of(AppType.customer)` 하드코딩 부분은 user role 기반 동적 전환으로 변경합니다.

### 2.2 회원가입 시 역할 선택

가입 마지막 단계에 **CUSTOMER / OWNER 라디오** 추가:
- CUSTOMER 선택 시 → 즉시 가입 완료, 손님 화면 진입
- OWNER 선택 시 → 가게 정보(상호명, 사업자번호, 주소) 추가 입력 → 승인 대기

### 2.3 OWNER 가입 승인제

| 단계 | 처리 |
|---|---|
| OWNER 가입 신청 | `users.status = PENDING` 으로 INSERT |
| 운영자 승인 | **운영자(우현호)가 Supabase 콘솔에서 DB 직접 수정** (`status = APPROVED`) |
| 미승인 OWNER 로그인 시도 | "승인 대기 중" 안내 화면 표시, 사장 화면 진입 차단 |
| 승인 후 로그인 | 사장 화면 진입 + 가게 정보 등록 + (추후) POS 연동 가능 |

> 별도 어드민 웹/Flutter 어드민 화면은 **만들지 않습니다** (캡스톤 범위 외).
> 운영 전환 시 어드민 콘솔 추가 가능.

---

## 3. 인증 방식 — A+B 혼합 (비용 0원 전략)

**총 3가지 인증 경로**를 지원합니다:

| 경로 | 본인확인 | 비용 | 비고 |
|---|---|---|---|
| 카카오 OAuth (기존) | 카카오가 처리 (면제) | 0원 | 이미 구현됨 |
| 이메일 OTP (신규, **B안**) | 이메일 인증 코드 | 0원 | Supabase Auth 무료 |
| 휴대폰 인증 (신규, **A안**) | Firebase Phone Auth | **0원 (테스트 모드)** | 가짜 번호로 시연 |

### 3.1 A안 — Firebase Phone Auth + 테스트 전화번호

**캡스톤 동안 비용 0원 보장 메커니즘**:

1. Firebase 콘솔에서 프로젝트 생성 → **Spark(무료) 플랜 유지** (카드 등록 X)
2. Authentication → Phone → "Phone numbers for testing" 메뉴에 가짜 번호 등록
   - 예: `+82 10-1234-5678` → 고정 OTP `123456`
   - 예: `+82 10-9999-0000` → 고정 OTP `654321`
3. 발표/시연/심사 시 위 번호로 휴대폰 인증 → **실제 SMS 발송 X**, 비용 0
4. 코드는 운영용과 100% 동일 (`signInWithPhoneNumber()`)

**졸업 후 운영 전환 시**:
- Firebase 콘솔에서 Blaze(종량제) 전환 + 카드 등록만 하면 실제 SMS 발송 시작
- 코드 수정 0줄
- 한국 SMS 단가: 약 75원/건 (Tier 2 추정)

**NestJS 검증 흐름**:
```
[Flutter] ──인증→ [Firebase] ──ID토큰→ [Flutter]
              ↓
[Flutter] ──ID토큰+가입정보→ [NestJS]
                                 ↓
                          firebase-admin SDK로 토큰 검증
                                 ↓
                          users 테이블에 phone_verified_at = now()
                                 ↓
                          자체 JWT 발급 (기존 카카오 패턴과 동일)
```

### 3.2 B안 — Supabase Auth 내장 이메일 OTP

**1순위 후보**: Supabase Auth의 이메일 OTP/매직링크
- 완전 무료, 가입자수 제한 없음
- 콘솔 토글만 켜면 동작
- Flutter → NestJS 원칙 유지를 위해 **NestJS가 Supabase Auth Admin API를 프록시**

**대안**: NestJS에서 Gmail SMTP로 6자리 코드 직접 발송
- Gmail 무료 SMTP 일일 500건 한도
- 인증 코드 생성·저장·만료를 NestJS가 직접 처리

### 3.3 카카오 가입자

- 본인확인 면제 (카카오가 이미 처리)
- `auth_provider = KAKAO`로 구분

---

## 4. DB 스키마 변경 사항

### 4.1 users 테이블 추가 컬럼

| 컬럼명 | 타입 | NULL | 기본값 | 용도 |
|---|---|---|---|---|
| `status` | ENUM | NOT NULL | `APPROVED` | `PENDING` / `APPROVED` / `REJECTED` |
| `auth_provider` | ENUM | NOT NULL | — | `KAKAO` / `EMAIL` / `PHONE` |
| `email_verified_at` | TIMESTAMP | NULL | NULL | 이메일 인증 완료 시각 |
| `phone_verified_at` | TIMESTAMP | NULL | NULL | 휴대폰 인증 완료 시각 |
| `password_hash` | TEXT | NULL | NULL | bcrypt 해시 (이메일 가입자만) |
| `phone_number` | TEXT | NULL | NULL | E.164 형식 (`+8210...`) |

### 4.2 기본값 정책

- 카카오/이메일 CUSTOMER 가입 → `status = APPROVED` (즉시 활성화)
- OWNER 가입 → `status = PENDING` (승인 대기)
- OWNER로 가입했지만 카카오로 로그인한 경우 → 본인확인 OK라도 `status = PENDING` 유지

### 4.3 owner_applications 테이블 (신규, 선택)

OWNER 가입 신청 시 가게 정보를 받기 위한 별도 테이블:
- `id`, `user_id` (FK), `business_name`, `business_number`, `address`
- `status` (PENDING/APPROVED/REJECTED), `created_at`, `reviewed_at`

> 단순화를 위해 `users` 테이블에 컬럼만 추가하고 별도 테이블은 만들지 않을 수도 있음. 구현 단계에서 결정.

---

## 5. 백엔드 신규 엔드포인트

```
POST   /api/auth/signup/email       이메일+비밀번호 가입 (인증 코드 발송)
POST   /api/auth/verify-email       이메일 OTP 검증 → 가입 완료
POST   /api/auth/verify-phone       Firebase ID 토큰 검증 → phone_verified_at 갱신
POST   /api/auth/login/email        이메일+비밀번호 로그인
POST   /api/auth/signup/phone       휴대폰만으로 가입 (Firebase ID 토큰 사용)
GET    /api/auth/me                 현재 로그인 유저 정보 (status 포함)
```

승인 차단 가드: 모든 OWNER 전용 엔드포인트는 `status = APPROVED` 체크 필수.

---

## 6. 프론트엔드 신규 화면

```
lib/features/auth/
├── login_screen.dart            (기존, 카카오 버튼 + "이메일로 시작" 버튼 추가)
├── signup_method_screen.dart    (신규: 카카오 / 이메일 / 휴대폰 선택)
├── signup_email_screen.dart     (신규: 이메일+비번 입력 → OTP 발송)
├── signup_email_verify_screen.dart (신규: OTP 6자리 입력)
├── signup_phone_screen.dart     (신규: 휴대폰 번호 입력 → Firebase 호출)
├── signup_role_screen.dart      (신규: CUSTOMER / OWNER 선택)
├── signup_owner_info_screen.dart (신규: 가게 정보 입력)
└── owner_pending_screen.dart    (신규: 승인 대기 안내)
```

---

## 7. 비용 요약

### 7.1 캡스톤 기간 (현재)

| 항목 | 비용 |
|---|---|
| Firebase Phone Auth (테스트 모드) | **0원** |
| Supabase Auth 이메일 OTP | **0원** |
| 카카오 OAuth | **0원** |
| Supabase DB | **0원** (무료 플랜) |
| **합계** | **0원** |

### 7.2 졸업 후 운영 전환 시 예상 비용

| 항목 | 단가 |
|---|---|
| Firebase Phone Auth (Blaze, 한국 SMS) | 약 75원/건 |
| Supabase Auth (이메일은 무료 유지) | 0원 |
| **대안: NHN Cloud SMS로 교체** | 9원/건 (단, 사업자등록번호 + 발신번호 등록 필요) |

---

## 8. 구현 우선순위

1. DB 스키마 변경 (users 테이블 컬럼 추가)
2. 이메일 가입/로그인 백엔드 엔드포인트 (B안 — 가장 단순)
3. 회원가입 화면 (이메일 흐름)
4. OWNER 역할 선택 + 승인 대기 처리
5. Firebase Phone Auth 통합 (A안)
6. main.dart의 AppType 동적 전환
7. (추후) 사장 화면 신설 — 별도 작업

---

## 9. 명세서 변경 영향

- `memory/project_spec_overview.md`의 "Q6 앱 분리 구조 미결" → **종결**
- `docs/LUNCHSYNC_SPECIFICATION.md`의 인증/회원가입 섹션 갱신 필요
- `docs/LUNCHSYNC_DTO.md`에 신규 DTO 추가 필요 (SignupEmailDto, VerifyEmailDto, VerifyPhoneDto 등)
- DB ENUM에 `user_status` (PENDING/APPROVED/REJECTED), `auth_provider` (KAKAO/EMAIL/PHONE) 추가
