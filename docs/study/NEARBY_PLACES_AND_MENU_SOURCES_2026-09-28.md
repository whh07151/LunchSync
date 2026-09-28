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
- 카카오디벨로퍼스 로그인 크롬 자동 제어는 Windows 컴퓨터 사용 도구와 브라우저 연결 도구 모두 `windows sandbox failed: helper_unknown_error: apply deny-read ACLs`로 시작에 실패했다. 기존 Chrome에는 디버깅 포트가 없어 별도 Playwright 세션으로 로그인된 탭을 이어받을 수도 없다. 따라서 무료 쿼터 적용 순서를 계정 화면에서 확인하거나 앱 설정을 실제로 ON으로 바꾸지 못했다.

## 2026-09-28 실제 제공자 확인

로컬 LunchSync 키로 Kakao Local 검색을 호출했을 때 HTTP 403 `App(LunchSync) disabled OPEN_MAP_AND_LOCAL service.`가 반환됐다. 따라서 현재 실제 주변 장소 조회는 성공하지 않았다. [카카오 공식 사용 방법](https://developers.kakao.com/docs/ko/kakaomap/common)에 따르면 앱 관리의 **카카오맵 > 사용 설정 > 상태 ON**이 필요하다. 2026-07-21부터 개발자 계정의 첫 활성화 앱만 무료 쿼터가 적용되며 두 번째 앱 또는 무료 한도 초과 사용에는 비즈월렛과 유료 API 설정이 필요할 수 있다. 앱 설정 및 비용 조건을 확인하기 전까지 카카오 탐색은 선택 기능으로 취급하고, 등록 식당 조회는 독립적으로 제공한다. 이 403은 카카오 로그인 성공 여부와 별개다.

## 남은 구현·검증

1. `menu_items`에 매장 확인 주체와 `price_verified_at`, 사진 업로드/저작권 정보, 출처 URL을 추가한다. 현재 `MANUAL`은 DB 기본값이므로 매장 확인 완료와 동의어로 쓰지 않는다.
2. 매장 사진 업로드 전용 Storage 버킷과 URL 허용 정책을 만들고 POS 화면에 촬영/업로드·교체·삭제 흐름을 붙인다. 현재 임의 외부 `imageUrl` 입력은 출시 전 제한해야 한다.
3. 등록 식당 거리 조회는 현재 bbox 안 최대 5,000건을 페이지 조회한 뒤 거리순 정렬한다. 규모가 커지면 DB 측 지리 인덱스/거리 정렬 RPC로 바꾼다.
4. 위치 권한 거부 시 수동 지역 검색, 실제 모바일·웹의 위치 변경, Kakao API 키/쿼터, HTTPS 프록시 로그의 좌표 비노출을 별도 확인한다. 가격을 실시간이라고 표시하려면 공급원의 갱신 계약과 확인 시각이 필요하다.

합성 검증은 서비스 단위에서 가상 식당 1,202·밀집 후보 5,001·메뉴 600건 및 Kakao 장소 45건을 생성한다. 가상 값은 테스트 프로세스 안에만 존재하며 실제 DB나 Kakao 서비스에는 삽입하지 않는다.
