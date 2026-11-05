# LunchSync v2 변경·보안 검토

검토일: 2026-11-04 (한국 시간). 대상: `D:/Development Projects/LunchSync`, 브랜치 `agent/reliability-observability`, HEAD `4497c4882553bc43407ce2827187ef151ce9ad1d` 및 미커밋 v2 변경. 파일의 줄 번호는 검토 당시 기준이다.

## 판단

현재 상태는 게시·운영 준비 완료로 판단할 수 없다. 신규 기능의 권한·원자성·실패 처리와 UI/API 연결에 수정이 필요하다. 기존 주문 RPC와 서버 가격 재계산, 결제 소유권·상태 검증은 보존해야 한다. 전면 재작성보다는 신규 변경의 안전 경계를 복구하는 편이 적절하다.

사용자의 조건은 문제가 없을 때 GitHub와 Notion을 최신화하는 것이다. 조건을 충족하지 않아 원격 쓰기·커밋·푸시·Notion 수정은 하지 않았다. 이후 사용자는 Gemini Argon용 보완 프롬프트를 요청했다. 애플리케이션 코드는 수정하지 않았으며 이 검토 문서와 수정 프롬프트, 의존성 감사 증빙만 추가했다.

## 실제 실행 결과

| 검사 | 결과 |
|---|---|
| `backend`: `npm test -- --runInBand` | 34개 스위트 중 33 통과·1 실패. 테스트 234 통과·2 실패. 설정 미지정/빈 문자열에서 SIMULATE 차단 기대 403, 실제 500. 안전장치 통과 후 테스트 DB 경로로 진입한 회귀이며 실제 결제가 발생했다는 증거는 아님. |
| `backend`: `npm run build` | 통과 |
| `flutter analyze --no-pub` | 통과, No issues found |
| `flutter test --no-pub` | 39 통과·7 실패. URL 검증 1건과 주문 검토 화면 Row overflow 관련 6건. `order_review_screen.dart:409`에서 가로 65px 초과. |
| `npm audit --json` | 전체 46개 영향 패키지: critical 2·high 8·moderate 35·low 1. 중복 의존 경로와 개발 도구 포함, 독립적인 취약점 46개라는 뜻은 아님. |
| `npm audit --omit=dev --json` | 운영 의존성 분류 18개 영향 패키지: critical 1·high 6·moderate 11. 원문 `V2_NPM_AUDIT_PROD_2026-11-04.json`. 실제 번들·런타임 도달성은 추가 판별 필요. |
| `git diff --check` | 오류 없음, 기존 LF/CRLF 경고 있음 |
| 제한적 비밀값 패턴 검사 | backend/src·lib·supabase·scripts·.github에서 검사한 private-key/AWS/GitHub/live-secret 패턴 일치 없음. Git 이력 전체·실제 환경파일·모든 비밀 형식을 검사한 결과는 아님. |
| GitHub 원격 HEAD 조회 | 포트폴리오 브랜치 HEAD는 로컬 HEAD와 같음. v2 미커밋 변경은 GitHub에 없음. |

운영 DB, Supabase Data API, 마이그레이션 적용, 실제 Toss 결제, 기기 UI, 새 SQL 동시성 계약 검사는 실행하지 않았다. 정적 분석 통과는 기능·보안 통과를 의미하지 않는다.

## 변경 범위

점주 재고·레시피·유통기한 관리, 조리 시작 시 재고 차감, 영업상태·운영안내, 메뉴 관리 확장, 공동 장바구니·세션 주문 조회, 주문 내역 보강, 바로 주문, 선결제 예약 연동과 주문 옵션 UI가 추가됐다. 추적 파일 30개 변경 외에 신규 화면·서비스·테스트·마이그레이션이 있다.

## 우선 수정 사항

### 1. 모의결제 허용이 기본 허용으로 변경됨 — P1

`backend/src/orders/orders.service.ts:309`의 `ALLOW_SIMULATED_PAYMENTS !== 'false'`는 설정 누락·빈 값도 허용한다. production 차단은 남아 있으므로 모든 운영 환경에서 승인 우회가 가능하다고 단정하면 안 된다. 그러나 NODE_ENV 오설정 환경에서도 명시적인 테스트 허용 없이 PAID가 만들어질 수 있다. 기존 `=== 'true'` 경계를 복구해야 한다. `lib/features/payment/order_review_screen.dart:70`도 SIMULATE를 기본으로 선택하고 실제 원탭 결제처럼 표시한다. 기본은 TOSS로 두고 모의결제는 명확한 테스트 기능으로 제한해야 한다.

### 2. 릴리스 HTTPS 검증 우회 — P1

`lib/core/config/app_config.dart:76`은 release에서 URL이 비어 있으면 검증을 건너뛴다. 임의 BACKEND_HOST가 HTTP로 조합되며 localhost HTTP도 허용한다. JWT와 요청 데이터가 안전하지 않은 경로로 갈 수 있다. release는 명시적인 HTTPS URL이 없으면 실패하고, 로컬 HTTP는 debug/profile 경로에서만 허용해야 한다. 기존 app_config_test 실패로 재현됐다.

### 3. 새 DB 테이블 권한 계약 누락 — P1, 노출은 환경 의존

`supabase/migrations/20261103000001_commercial_inventory_and_shared_cart.sql:5`의 두 테이블에 RLS·권한 회수·서비스 역할 GRANT가 없다. 기존 공개 역할 기본 권한을 상속하면 NestJS를 우회한 조회·변조 위험이 있고, 권한이 기본 회수된 환경에서는 서비스 호출이 실패할 수 있다. 실제 노출 여부는 미검증이다. RLS 활성화와 PUBLIC/anon/authenticated 권한 회수, 필요한 service_role 권한을 명시하고 선언형 스키마 `supabase/schemas/lunchsync.sql`도 함께 맞춰야 한다. SQL로 만든 테이블의 RLS는 명시적인 검토가 필요하다. [Supabase 공식 문서](https://supabase.com/docs/guides/database/postgres/row-level-security).

### 4. 재고 교체가 비원자적이며 실패를 숨김 — P1

`backend/src/pos/pos.service.ts:998`은 기존 재고 전체 삭제 후 입력을 변환·삽입한다. 컨트롤러는 필드 누락도 빈 목록으로 처리한다. 중복 ID·null 항목·잘못된 숫자나 INSERT 장애로 기존 재고가 소실될 수 있다. 점주 본인 매장 접근은 검증하므로 타 매장 무권한 삭제 문제로 분류하지 않는다. 필수 중첩 DTO, 전체 사전검증, 명시적인 빈 배열 구분, 원자적 교체 RPC와 오류 전파가 필요하다.

### 5. 동시 주문 재고 차감 불일치 — P1

`backend/src/pos/pos.service.ts:1028`의 read-modify-write는 두 주문이 각각 재고 10에서 2를 차감할 때 모두 8을 저장할 수 있다. `:572`에서 차감 전에 주문 상태가 먼저 반영되고 실패를 숨겨 재시도로 복구되지 않는다. 상태 전이·차감의 트랜잭션 경계, 재고 행 잠금, 주문별 멱등성을 구현해야 한다.

### 6. 공동 장바구니 권한·정합성 — P1/P2

`sessions.service.ts:642`는 클라이언트 메뉴명·가격·수량을 검증 DTO 없이 저장하고 쓰기 오류를 검사하지 않는다. 다른 식당 메뉴·종료 세션 입력도 확인하지 않는다. 현재 주문 생성은 서버 가격을 다시 계산하므로 이것만으로 결제 금액 변조가 입증된 것은 아니다. 하지만 공동 주문 화면을 잘못 표시할 수 있다. `:686`은 멤버 한 명의 DELETE로 세션 전체를 삭제한다. 본인 항목 삭제와 호스트의 명시적 전체 초기화를 분리해야 한다.

`menu_screen.dart`는 첫 담기·수량 감소·합치기를 서버에 반영하지 않고 + 버튼 일부만 반영한다. 조회도 입장 시 한 번이며 실시간 갱신이 없다. 전역 로컬 카트와 세션 DB 카트의 기준 및 실패·재시도 정책이 필요하다.

### 7. 선결제 예약이 실제 좌석을 확보하지 않음 — P2

`orders.service.ts:655`는 좌석 조회 후 예약만 삽입하며 좌석 홀딩을 하지 않는다. 기존 OPEN 예약·동시 결제·고유 order_id를 고려하지 않는다. 각자 결제해도 매번 전체 세션 인원으로 예약하며 다른 멤버의 미결제 카트를 삭제한다. Toss confirm 경로에는 이 예약 함수가 연결되어 있지 않다. 원자적인 좌석 확보까지 구현하지 않으면 '예약 요청' 수준으로 안내해야 한다.

### 8. 주문 옵션이 실제 주문에 전달되지 않음 — P2

`order_review_screen.dart:136`에서 이용 방식·1/N·요청사항을 보내지 않는다. 포장도 같은 매장 방문 예약으로 처리될 수 있다. 특히 알레르기 제외 요청처럼 보이는 입력은 사용자가 전달됐다고 믿을 수 있다. 서버 저장·POS 전달까지 구현하거나 미지원 선택·입력을 제거/비활성화해야 한다. 1/N 금액 계산 표시와 실제 분할 결제를 구분해야 한다.

### 9. 신규 화면 오류·바로 주문 세션 선택 — P2

`menu_screen.dart:688`은 공동 카트만 있고 주문은 0건일 때도 추적 버튼에서 `_sessionOrders.first`에 접근한다. 주문이 있을 때만 추적 동작을 허용해야 한다.

`menu_screen.dart:343`은 상세 화면이 다른 식당 세션을 피하려 null을 넘겨도 첫 비종료 세션을 다시 선택한다. 같은 식당의 주문 가능 세션만 재사용하거나 명시적인 새 주문 의도를 전달해야 한다.

`order_review_screen.dart:409`는 테스트에서 65px overflow를 일으킨다. Wrap/Flex 등으로 좁은 화면과 큰 글자에서 접근 가능한 배치를 검증해야 한다.

### 10. 의존성 취약점 — 기존 문제와 분리

v2의 package-lock 변경은 없으므로 모두 이번 변경이 새로 만들었다고 볼 수 없다. 운영 의존성 감사에는 proxy-addr 2.0.7 critical, multer 2.2.0 및 기타 high 경고가 있다. [proxy-addr 공식 권고](https://github.com/advisories/GHSA-jqcg-44mw-7w3h)는 특정 신뢰 서브넷 설정에서의 IP 위조를 설명한다. 현재 main.ts는 숫자 hop 수를 설정하므로 해당 조건이 그대로 성립한다고 단정하지 않는다. 패치 대상이지만 실제 악용 가능성과 등급은 구분한다. Multer 업로드 경로가 있으므로 권한·크기 제한을 포함해 영향 조건을 검토해야 한다. 모든 감사 경고를 독립 취약점이나 외부 공격 성공으로 해석하지 않는다.

## 수정 순서와 재검토

1. 모의결제·HTTPS·DB 역할 경계 복구.
2. 재고 교체/차감 원자성과 실패 복구, 카트 삭제 권한과 입력 검증.
3. 공동 카트 동기화, 주문 세션 선택, 실제 결제 예약 연동과 미지원 UI 정리.
4. 의존성 호환 패치 및 전체 테스트를 CI 필수 검사로 연결.
5. 실제 SQL 역할·트랜잭션·동시성 검사와 두 사용자 UI 검증 후 결과 재검토.

수정 지시문: `GEMINI_ARGON_V2_FIX_PROMPT_2026-11-04.md`. 원격 게시 재개 여부는 수정본 재검토 결과로 판단한다.
