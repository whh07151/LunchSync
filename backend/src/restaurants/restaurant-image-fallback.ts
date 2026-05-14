// ══════════════════════════════════════════════════════════
// 파일 역할: 식당 image_url 자동 폴백 헬퍼 (3층 안전망 공유 로직)
//
// 배경 (2026-05-14):
//   사장님 피드백 "메뉴넣으면서 이미지도 넣어달라니까" 대응으로
//   d379484 에서 restaurants.image_url 컬럼 select 는 살렸지만
//   1) 시드 데이터(seed-restaurants.ts) — image_url 필드 자체가 없음
//   2) 크롤 결과(crawl.service.ts saveToDb) — image_url 저장 누락
//   3) 기존 DB 레코드 — image_url IS NULL 상태로 다수 존재
//   세 경로 모두 카드/지도/상세에서 회색 박스로 보임 → 시연 임팩트 0.
//
// 해결책 (3층 안전망):
//   1) 시드 코드 — buildFallbackImageUrl() 로 카테고리+이름 매핑
//   2) 크롤 서비스 — DB 저장 직전에 동일 헬퍼로 빈 값 채우기
//   3) 응답 매핑 — getRestaurants/getRestaurantById 가 응답 단에서
//                  최후 방어층으로 한 번 더 폴백 (DB 가 누락이어도 안전)
//   + 마이그레이션 SQL (2026-05-14-fill-empty-image-urls.sql) 로
//     이미 들어간 빈 image_url 일괄 UPDATE
//
// 이미지 소스:
//   Unsplash Source API — https://source.unsplash.com/{w}x{h}/?{keywords}
//   - CORS·인증 없이 즉시 사용 가능
//   - 키워드 매칭 실패 시 Unsplash 가 일반 음식 사진으로 자동 대체
//   - 같은 키워드 + 캐시 키 조합이면 동일 사진을 안정적으로 반환
//
// 카테고리 매핑:
//   한식 → korean,food / 일식 → japanese,sushi / 중식 → chinese,noodle
//   양식 → western,pasta / 분식 → street-food,tteokbokki
//   카페 → cafe,coffee / 패스트푸드 → burger,fastfood
//   면류 → noodle,ramen / (기타) → korean,food (안전 기본값)
// ══════════════════════════════════════════════════════════

// 카테고리별 Unsplash 검색 키워드 매핑.
// 같은 카테고리 식당이 비슷한 사진을 받도록 한국어 카테고리 ↔ 영어 키워드 1:1 매핑.
// 시드 데이터 카테고리(한식/일식/중식/양식/분식/카페)와 크롤 mapCategory() 출력
// (한식/중식/일식/양식/분식/카페/패스트푸드/아시안/기타) 둘 다 커버.
const CATEGORY_KEYWORDS: Record<string, string> = {
  한식: 'korean,food',
  일식: 'japanese,sushi',
  중식: 'chinese,noodle',
  양식: 'western,pasta',
  분식: 'street-food,tteokbokki',
  카페: 'cafe,coffee',
  패스트푸드: 'burger,fastfood',
  면류: 'noodle,ramen',
  아시안: 'asian,food',
  기타: 'korean,food', // 최후 안전값 — 한식 비중이 가장 큼
};

// ── 카테고리 → Unsplash 키워드 변환 ───────────────────────
// 공백·대소문자·앞뒤 trim 안전 처리. 매핑 실패 시 한식 키워드로 폴백.
function getCategoryKeyword(category?: string | null): string {
  if (!category) return CATEGORY_KEYWORDS.기타;
  const trimmed = String(category).trim();
  return CATEGORY_KEYWORDS[trimmed] ?? CATEGORY_KEYWORDS.기타;
}

// ── 식당 이름 키워드 추출 ─────────────────────────────────
// Unsplash 검색의 보조 키워드. 한글 식당명은 URL 인코딩되어 매칭 정확도가
// 떨어지지만, 같은 이름이면 같은 사진을 받게 해주는 "안정 시드" 역할.
// 너무 긴 이름은 첫 6자로 잘라 URL 길이 제한 방지.
function getNameSlug(name?: string | null): string {
  if (!name) return '';
  const trimmed = String(name).trim().slice(0, 6);
  return encodeURIComponent(trimmed);
}

// ──────────────────────────────────────────────────────────
// 식당 카드/상세 이미지용 폴백 URL 생성
// ──────────────────────────────────────────────────────────
// 패턴: https://source.unsplash.com/400x300/?korean,food,한솥
//   - 400x300 — 카드 썸네일·상세 헤더 모두 커버하는 표준 사이즈
//   - 카테고리 키워드 + 이름 슬러그 조합으로 같은 식당은 같은 사진 안정 매칭
//
// 호출 시점:
//   1) 시드 코드(seed-restaurants.ts) — RESTAURANTS 리스트 매핑 시
//   2) 크롤 서비스(crawl.service.ts saveToDb) — DB INSERT 직전
//   3) 응답 매핑(restaurants.service.ts) — DB 가 비어있어도 최후 방어
export function buildFallbackImageUrl(
  category?: string | null,
  name?: string | null,
): string {
  const keyword = getCategoryKeyword(category);
  const slug = getNameSlug(name);
  if (slug.length === 0) {
    return `https://source.unsplash.com/400x300/?${keyword}`;
  }
  return `https://source.unsplash.com/400x300/?${keyword},${slug}`;
}

// ──────────────────────────────────────────────────────────
// 빈 값 폴백 헬퍼 — image_url 이 null/undefined/공백이면 자동 생성
// ──────────────────────────────────────────────────────────
// 이미 image_url 이 있으면(네이버 thumUrl 등) 그대로 유지.
// 시드/크롤/응답 3층 모두 이 함수를 거치면 빈 값이 절대 통과하지 않음.
export function ensureRestaurantImageUrl(
  imageUrl: string | null | undefined,
  category?: string | null,
  name?: string | null,
): string {
  if (imageUrl && imageUrl.trim().length > 0) {
    return imageUrl;
  }
  return buildFallbackImageUrl(category, name);
}
