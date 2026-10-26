# 주변 장소와 메뉴 가격·사진 출처 검토 (2026-09-28)

## 채택한 데이터 경로

- 위치: Flutter 기기 GPS를 사용자 동의 후 읽고, 좌표는 JSON 본문의 `POST /api/crawl/nearby`에만 전달한다. 서버 접근 로그에는 좌표를 기록하지 않는다.
- 장소 발견: [Kakao Local 카테고리 검색](https://developers.kakao.com/docs/ko/kakaomap/rest-api)의 `FD6` 음식점 결과를 요청마다 최대 3페이지/45건 조회한다. 장소명·주소·거리·카카오 상세 링크만 일회성으로 반환하며 앱 DB에 저장하지 않는다. 로컬 서버는 명시적 설정에서 Kakao REST 키만 읽고, 요청 제한과 1분 메모리 캐시를 둔다.
- 주문 가능한 식당: 별도 `restaurants` DB에서 사용자 반경 1km 내 등록 식당을 조회한다. 카카오 검색 결과를 자동으로 주문 가능한 식당으로 바꾸지 않는다.
- 메뉴: POS/매장 관리에서 등록한 `source=MANUAL`, `is_available=true`인 메뉴만 장바구니·주문 경로에 사용한다. 수집·AI 추정 메뉴는 상세의 참고 정보로만 보이며 가격을 확인 필요로 표시한다. 서버도 주문 생성 시 출처와 판매 가능 상태를 재검사한다.
- 사진: 기존 `source.unsplash.com` 검색 URL은 실제 매장/메뉴 사진이 아니므로 API에서 숨긴다. 수집·AI 메뉴의 외부 이미지는 메뉴 사진으로 내보내지 않는다. 사진이 없으면 앱의 카테고리 일러스트 폴백을 사용한다.

## 제공자 조사

| 경로 | 메뉴별 가격·사진 | 활용 판단 |
|---|---|---|
| [Kakao Local](https://developers.kakao.com/docs/ko/kakaomap/rest-api) | 응답에 없음 | 주변 장소 발견만 사용 |
| [Google Places (New)](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places) | 식당 단위 `priceRange`와 장소 사진은 있으나 메뉴 항목별 가격·사진 연결은 없음 | 장소 검색의 대안. [FieldMask에 따른 과금](https://developers.google.com/maps/billing-and-pricing/sku-details), [사진 저작자 표시·캐시 제한](https://developers.google.com/maps/documentation/places/web-service/place-photos) 확인 필요 |
| [NAVER API HUB 지역검색](https://api.ncloud-docs.com/docs/naver-api-hub-search-local) | 없음 | 메뉴 공급원으로 사용하지 않음 |
| [Google Business Profile Food Menus](https://developers.google.com/my-business/content/update-food-menus) | 메뉴별 가격과 연결된 사진 키를 지원 | [API 접근 승인·매장 소유자/관리자 OAuth 권한](https://developers.google.com/my-business/content/faq)이 있는 매장에 한해 향후 연동 후보 |

가장 빠르고 신뢰할 수 있는 메뉴 확보 방법은 **LunchSync 매장 화면에서 사장이 메뉴명·가격·품절·직접 촬영한 사진을 등록하고 갱신**하는 것이다. 제휴 매장이 늘면 동의를 받은 POS 피드나 Google Business Profile 같은 매장 권한 연동을 추가한다. 웹 검색·비공개 엔드포인트·AI 생성 결과를 현재 판매 가격으로 저장하지 않는다.

## 메뉴 가격·사진 수집 우선순위

1. **매장 직접 입력/업로드**: 매장 담당자가 메뉴명·옵션·현재가·품절 여부를 등록하고 본인이 촬영했거나 사용 허락을 받은 사진을 올린다. 변경 주체와 확인 시각을 기록한다. 초기 LunchSync에 가장 적합하다.
2. **매장이 제공한 CSV·POS 연동**: 매장별 명시적 동의와 메뉴 ID 매핑이 있으면 정기 동기화한다. 삭제·품절·옵션 가격도 동기화하고 충돌 시 담당자 확인을 요구한다. 공급처가 실제로 연동을 허용하는지 계약/API 문서로 확인한 뒤 구현한다.
3. **매장 권한으로 승인된 Google Business Profile Food Menus**: 항목별 가격과 연결된 사진 키를 읽을 수 있는 구조지만, API 프로젝트 승인과 해당 매장의 소유자/관리자 권한 또는 OAuth 동의가 필요하다. 임의의 주변 식당 메뉴를 대량 수집하는 공개 API가 아니다.
4. **메뉴판 사진 OCR**: 매장이 제공한 원본 사진에서 메뉴·가격 입력 초안을 만드는 보조 기능으로만 사용한다. 옵션·원화 표기·할인가·품절·촬영일이 틀릴 수 있으므로 담당자가 확인하기 전에는 주문 가격으로 공개하지 않는다.

각 항목에는 `source`, `merchantVerifiedAt`, `lastSyncedAt`, `photoRights`, `isAvailable`을 구분해 둔다. `lastSyncedAt`만으로 현행 가격이 보장되지는 않는다. 확인되지 않은 가격은 숫자를 확정 가격처럼 표시하지 않고 매장 확인 링크/상태를 보여 준다. 장소 대표 사진과 특정 음식 사진도 서로 구분한다. Google Places의 장소 사진은 메뉴 항목별 사진이 아니며 [저작자 표시와 캐시 제한](https://developers.google.com/maps/documentation/places/web-service/place-photos)을 따른다.

### 사용자 요청에 따른 참고 가격·이미지 표시

- 판매가 미확인 메뉴는 같은 식당의 같은 종류 `MANUAL` 등록 메뉴 가격의 평균(500원 단위 반올림)을 우선 표시한다. 없으면 해당 식당 전체 등록 메뉴 평균, 다시 없으면 기존 식당 가격대 환산값을 **`예상`**으로 표시한다. 비교 자료와 식당 가격대 모두 없으면 숫자를 만들지 않고 `가격 확인 필요`로 둔다. `MANUAL`은 DB 기본값이므로 이 평균도 매장 검증 가격이나 공공 통계 평균을 뜻하지 않는다.
- 예상가의 기준을 메뉴 행에 함께 표시하며 참고 메뉴는 기존처럼 주문/결제에 사용할 수 없다. 정확한 금액은 매장 등록·확인 후에만 주문 경로에 들어간다.
- 실제 메뉴 사진이 없으면 앱에 포함한 생성 이미지 3종(일반 식사·면·카페)을 사용하고 사진 위에 `예시`를 표시한다. 이는 특정 식당 또는 특정 메뉴의 실제 사진이 아니다. 생성 프롬프트는 일반 음식의 자연광 사진, 브랜드·인물·문구 없음으로 설정했다.
- 현호 Chrome 연결은 손상된 Windows sandbox ACL 상태 파일을 보존 이동한 뒤 복구했다. 카카오 개발자 콘솔에서 무료 쿼터 적용 앱과 지도 사용 상태를 직접 확인했다.

## 2026-09-28 실제 제공자 확인

초기 로컬 키로 Kakao Local 검색을 호출했을 때 HTTP 403 `App(LunchSync) disabled OPEN_MAP_AND_LOCAL service.`가 반환됐다. 당시 키가 지도 OFF 앱에 속했기 때문이다. [카카오 공식 사용 방법](https://developers.kakao.com/docs/ko/kakaomap/common)에 따르면 앱 관리의 **카카오맵 > 사용 설정 > 상태 ON**이 필요하며, 2026-07-21부터 개발자 계정의 첫 활성화 앱만 무료 쿼터가 적용된다. 아래의 기존 무료 앱 키로 로컬 장소 조회를 복구했다. 카카오 로그인 앱은 그대로 유지한다.

## 남은 구현·검증

1. `menu_items`에 매장 확인 주체와 `price_verified_at`, 사진 업로드/저작권 정보, 출처 URL을 추가한다. 현재 `MANUAL`은 DB 기본값이므로 매장 확인 완료와 동의어로 쓰지 않는다.
2. 매장 사진 업로드 전용 Storage 버킷과 URL 허용 정책을 만들고 POS 화면에 촬영/업로드·교체·삭제 흐름을 붙인다. 현재 임의 외부 `imageUrl` 입력은 출시 전 제한해야 한다.
3. 등록 식당 거리 조회는 현재 bbox 안 최대 5,000건을 페이지 조회한 뒤 거리순 정렬한다. 규모가 커지면 DB 측 지리 인덱스/거리 정렬 RPC로 바꾼다.
4. 위치 권한 거부 시 수동 지역 검색, 실제 모바일·웹의 위치 변경, Kakao API 키/쿼터, HTTPS 프록시 로그의 좌표 비노출을 별도 확인한다. 가격을 실시간이라고 표시하려면 공급원의 갱신 계약과 확인 시각이 필요하다.

합성 검증은 서비스 단위에서 가상 식당 1,202·밀집 후보 5,001·메뉴 600건 및 Kakao 장소 45건을 생성한다. 가상 값은 테스트 프로세스 안에만 존재하며 실제 DB나 Kakao 서비스에는 삽입하지 않는다.

## 2026-09-28 카카오 개발자 콘솔 실확인 및 로컬 복구

현호 계정의 카카오 개발자 콘솔에서 `lunchsync(가칭)`(앱 ID 1423393)은 카카오맵 ON이며 무료 쿼터 대상임을 확인했다. 현재 카카오 로그인 앱 `LunchSync`(앱 ID 1534395)는 카카오맵 OFF다. [카카오맵 공식 사용 방법](https://developers.kakao.com/docs/ko/kakaomap/common)에 따르면 무료 쿼터는 개발자 계정의 첫 번째 활성화 앱에만 제공된다. 콘솔은 무료 쿼터 적용 앱을 비활성화해도 변경할 수 없다고 명시한다. 따라서 새 앱의 지도나 유료 API/비즈월렛은 켜지 않았다.

로컬 `backend/.env`의 `KAKAO_REST_API_KEY`는 새 앱의 키여서 장소 검색이 HTTP 403, 백엔드 `/api/crawl/nearby`가 503이었다. 키 지문으로 앱 소속을 대조하고 기존 무료 앱의 기본 REST 키를 로컬 Git 제외 환경 파일에만 설정했다. 로컬 백엔드를 재시작한 뒤 `node backend/scripts/local-nearby-smoke.cjs`가 통과했다. 서울시청 테스트 좌표 반경 1km에서 카카오 장소 45건을 조회했고 등록 식당 1건을 별도 조회했으며 `restaurants`·`menu_items` 건수는 변하지 않았다. 장소 발견은 실제 메뉴별 가격·사진 제공이 아니므로 주문은 등록·확인된 메뉴에서만 허용한다.

현호 Chrome의 `http://localhost:8080` 초기 화면은 시각 확인했다. Android 에뮬레이터에서 서울시청 가상 위치와 합성 계정·세션으로 AI 추천 화면, 카카오 지도 타일·식당 핀, 리스트 전용 보기와 지도 복귀를 확인했다. 이는 운영 메뉴·실기기 GPS·실결제 검증을 뜻하지 않는다.

## 로컬 지도 앱·웹 빌드

카카오 로그인 앱(1534395)과 지도 무료 앱(1423393)의 키를 혼동하면 앱 로그인은 되더라도 지도가 빈 화면이 된다. 로그인 설정을 유지하고, 지도 무료 앱의 **JavaScript 키**를 Git 제외 파일 `.local/kakao-map-js-key.local`에 한 줄로 저장한다. 기존 지도 앱의 JavaScript SDK 허용 도메인에는 `http://localhost:8080`이 등록되어 있다. 지도 REST 키는 별도 Git 제외 `backend/.env`의 `KAKAO_REST_API_KEY`에 둔다.

`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-local-client.ps1 -Target apk` 또는 `-Target web`을 실행하면 스크립트가 키 형식을 확인하고 Git 제외 Dart define 파일을 만들어 지도 키를 빌드에만 전달한다. 에뮬레이터의 새 APK에서 지도와 리스트 전환을 확인했고, 지도 키가 로그인 SDK 키를 덮어쓰지 않는 구조다. 새 기기나 브라우저 origin에서는 카카오 콘솔의 JavaScript SDK 도메인 등록을 확인해야 한다.

## Android 위치 핀 이동 검증

잠긴 `geolocator_android 4.6.2`는 첫 위치 스트림 설정을 뒤 구독자에게도 공유한다. 홈 화면이 먼저 500m 필터로 구독해 지도 화면의 10m 설정이 무시되는 문제를 에뮬레이터에서 재현했다. 지도에 머문 채 500m 미만을 이동하면 핀이 고정되고, 500m 이상 이동하면 이벤트가 왔다. 홈 스트림을 지도와 동일한 10m로 맞추되 홈의 식당 정보 갱신은 100m 이상, 카카오 장소 재조회는 기존 500m 이동 또는 5분 기준으로 제한했다. 서울시청 가상 위치에서 약 50m 이동한 뒤 지도 타일/식당 핀이 유지되고 파란 위치 핀만 즉시 옮겨진 것을 Android 에뮬레이터에서 확인했다. 이 검증은 에뮬레이터의 모의 GPS이며 실기기 위치 정확도 검증은 아니다.
