import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { ensureRestaurantImageUrl } from './restaurant-image-fallback';
import { normalizePriceRangeToWon } from './price-range-normalizer';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 비즈니스 로직
//
// 현재: 기본 CRUD + 예산/카테고리 필터링
// 추후: CORE-07(추천 엔진)에서 점수 기반 정렬 추가 예정
// ══════════════════════════════════════════════════════════

export interface GetRestaurantsQuery {
  category?: string;
  maxPrice?: number;
  limit?: number;
  offset?: number;
  // 위치 기반 필터 (2026-05-12 추가) — 사용자 GPS 좌표 + 반경(m).
  // lat/lng/radius 모두 제공 시 Haversine 으로 반경 내만 반환.
  lat?: number;
  lng?: number;
  radius?: number;
}

@Injectable()
export class RestaurantsService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── GET /restaurants ──────────────────────────────────
  // 필터 조건으로 식당 목록 조회
  async getRestaurants(query: GetRestaurantsQuery) {
    // 2026-05-13 image_url 컬럼 select 추가:
    //   클라이언트 RestaurantDto.imageUrl 매핑용. 사장님 피드백 "사진 잘 보였으면"
    //   대응. 카드/상세에서 사진 렌더링이 가능해짐 (없으면 FoodImage 폴백 동작).
    //
    // 2026-05-14 rating 컬럼 select 추가:
    //   사장님 피드백 "네이버나 구글로 식당 평점 조사한 거 맞아?" 대응.
    //   CrawlService 가 네이버 reviewScore 를 수집해 restaurants.rating 에 저장
    //   하게 됐으므로 클라이언트로도 함께 내려준다. UI 에서 "⭐ 4.2" 표기.
    // 2026-05-31 WOW#1 todays_note 컬럼 select 추가:
    //   사장이 POS/사장앱에서 입력한 "오늘의 한 줄" 메시지.
    //   응답 camelCase 키 todaysNote 로 변환되어 손님 추천 카드 노란 띠와
    //   추천 점수 가중치(+5)에 사용된다. NULL 이면 UI 에 노출되지 않음.
    let qb = this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, rating, todays_note, created_at');

    if (query.category) {
      qb = qb.eq('category', query.category);
    }
    if (query.maxPrice) {
      qb = qb.lte('price_range', query.maxPrice);
    }

    qb = qb.order('created_at', { ascending: false });

    if (query.limit) {
      qb = qb.limit(query.limit);
    }
    if (query.offset) {
      qb = qb.range(query.offset, query.offset + (query.limit ?? 20) - 1);
    }

    const { data, error } = await qb;

    if (error) {
      throw new Error(`식당 목록 조회 실패: ${error.message}`);
    }

    // 위치 기반 반경 필터 (2026-05-12 추가):
    //   query.lat/lng/radius 모두 있으면 Haversine 으로 반경 내 식당만 반환.
    //   추후 PostGIS 도입 시 DB 쿼리 단에서 처리하도록 이동 가능.
    let rows = data ?? [];
    if (query.lat != null && query.lng != null) {
      const radius = query.radius ?? 1000; // 기본 1km
      rows = rows.filter((r: any) => {
        if (r.lat == null || r.lng == null) return false;
        return haversineMeters(query.lat!, query.lng!, r.lat, r.lng) <= radius;
      });
    }

    return rows.map((r: any) => ({
      id: r.id,
      name: r.name,
      category: r.category,
      priceRange: r.price_range,
      // 2026-05-14: price_range 출처(시드/크롤/Gemini)가 섞여 있어
      // 단위가 들쭉날쭉. 프론트가 매번 휴리스틱을 돌리지 않도록 백엔드가
      // 추정 원(₩) 단위 평균가를 동봉. null 이면 "가격 정보 없음" 의미.
      // 헬퍼: price-range-normalizer.ts (lib/core/utils/normalizer.dart 와 동기).
      estimatedPriceWon: normalizePriceRangeToWon(r.price_range),
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      // 2026-05-14: 응답 단 최후 방어층. 시드/크롤이 누락된 옛 레코드도
      // 카테고리·이름 기반 Unsplash URL 로 자동 채워서 내려보낸다.
      // (DB 마이그레이션이 적용되기 전 EC2 상태에서도 시연 안전.)
      imageUrl: ensureRestaurantImageUrl(r.image_url, r.category, r.name),
      // 네이버 플레이스 평점 (0.0~5.0). 미수집 식당은 null.
      // 클라이언트 RestaurantDto.rating 에 매핑되어 ⭐ 칩으로 표시됨.
      rating: r.rating != null ? Number(r.rating) : null,
      // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄".
      //   null 이면 손님 카드에서 노란 띠 숨김. 비어있는 문자열도 동일 취급
      //   되도록 trim 후 길이 0 인 경우 명시적으로 null 로 normalize.
      todaysNote:
        typeof r.todays_note === 'string' && r.todays_note.trim().length > 0
          ? r.todays_note
          : null,
      createdAt: r.created_at,
    }));
  }

  // ── GET /restaurants/:id ──────────────────────────────
  async getRestaurantById(id: string) {
    // 2026-05-14 rating 컬럼 select 추가 — 상세 화면에서도 평점 표시.
    // 2026-05-31 todays_note 컬럼 select 추가 — 상세 화면 상단 노란 띠 노출용.
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, rating, todays_note, created_at')
      .eq('id', id)
      .single();

    if (error || !data) {
      throw new NotFoundException('식당을 찾을 수 없습니다.');
    }

    // 2026-05-15: 사장님 발견 "식당 정보 표시 불안정" 회귀 안전망.
    // 모든 필드에 명시적 fallback — null/empty 시에도 화면이 빈 채로
    // 머물지 않게. ensureRestaurantImageUrl 은 이미 3층 안전망.
    return {
      id: data.id,
      name: data.name ?? '식당',
      category: data.category ?? '기타',
      priceRange: data.price_range,
      estimatedPriceWon: normalizePriceRangeToWon(data.price_range),
      address: data.address ?? '',
      lat: data.lat,
      lng: data.lng,
      imageUrl: ensureRestaurantImageUrl(data.image_url, data.category, data.name),
      rating: data.rating != null ? Number(data.rating) : null,
      // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄".
      //   목록 응답과 동일 정규화 규칙 적용 (빈 문자열 → null).
      todaysNote:
        typeof data.todays_note === 'string' &&
        data.todays_note.trim().length > 0
          ? data.todays_note
          : null,
      createdAt: data.created_at,
    };
  }

  // ── Haversine 거리 계산 ──────────────────────────────
  // 두 위경도 좌표 사이 지표면 거리(m). recommendations.service 와 동일 로직.
  // PostGIS 미사용 환경에서 서비스 단 임시 필터링 용도.
  // ── GET /restaurants/:id/menus ────────────────────────
  async getMenusByRestaurant(restaurantId: string) {
    const { data, error } = await this.supabase.client
      .from('menu_items')
      .select('id, name, price, category, description, image_url')
      .eq('restaurant_id', restaurantId)
      .order('category')
      .order('price');

    if (error) {
      throw new Error(`메뉴 조회 실패: ${error.message}`);
    }

    // 2026-05-15: menu_items 의 image_url 이 null/empty 인 옛 레코드도
    // 카테고리·이름 기반 Unsplash URL 로 자동 폴백. 시드/크롤 누락 안전망.
    const menus = (data ?? []).map((m) => ({
      id: m.id,
      name: m.name ?? '메뉴',
      price: m.price ?? 0,
      category: m.category ?? '기타',
      description: m.description ?? '',
      imageUrl:
        m.image_url && String(m.image_url).trim().length > 0
          ? m.image_url
          : `https://source.unsplash.com/400x300/?korean,food,${encodeURIComponent(m.name ?? 'meal')}`,
    }));

    // DTO 기준: { categories[], menus[] } 구조로 반환
    // categories: '전체' + 중복 제거된 카테고리 목록
    const uniqueCategories = [...new Set(menus.map((m) => m.category).filter(Boolean))];
    const categories = ['전체', ...uniqueCategories];

    return { categories, menus };
  }

  // ══════════════════════════════════════════════════════════
  // WOW#5 단골 랭킹 (2026-05-31 추가)
  // ══════════════════════════════════════════════════════════
  //
  // 핵심: 손님이 한 식당에 몇 번 픽업 완료했는지 카운트 → 등급(NORMAL/REGULAR/VIP) 결정.
  // 이 식당 상세 헤더 뱃지 + 픽업 완료 토스트 + 사장 측 VIP 알림에서 동시 사용.
  //
  // 카운트 기준 (성능):
  //   - orders 테이블에서 head: true + count: 'exact' 옵션으로 전체 ROW 페치 없이
  //     COUNT 만 받아옴. GROUP BY 가 필요한 게 아니라 단일 (user, restaurant) 카운트.
  //   - 인덱스: orders(user_id, restaurant_id, status) 합성 인덱스가 권장되지만
  //     기존 user_id/restaurant_id 개별 인덱스만으로도 일일 트래픽엔 충분.
  async getLoyalty(
    restaurantId: string,
    userId: string,
  ): Promise<{
    visitCount: number;
    rank: 'NORMAL' | 'REGULAR' | 'VIP';
    isFirstTime: boolean;
  }> {
    // count: 'exact' + head: true → 결과 행은 안 받고 카운트만.
    // 같은 식당에서 같은 손님의 COMPLETED 주문 개수 = 방문(픽업) 횟수.
    const { count, error } = await this.supabase.client
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('restaurant_id', restaurantId)
      .eq('status', 'COMPLETED');

    if (error) {
      throw new Error(`단골 카운트 조회 실패: ${error.message}`);
    }

    const visitCount = count ?? 0;
    return {
      visitCount,
      rank: resolveLoyaltyRank(visitCount),
      // isFirstTime 의 정의: "지금 이 방문이 첫 픽업인가?" 가 아니라
      // "이 식당과의 누적 방문이 1회인가" — 픽업 완료 직후 토스트의
      // "이번이 첫 방문이에요" 카피용. visitCount === 1 이면 true.
      isFirstTime: visitCount === 1,
    };
  }
}

// ══════════════════════════════════════════════════════════
// 단골 등급 헬퍼 (다른 서비스에서도 재사용 가능하도록 export)
// ══════════════════════════════════════════════════════════
//
// 규칙(고정 — 프론트 뱃지 색과 1:1 대응):
//   0~2회 → NORMAL  (흰 배경 뱃지)
//   3~4회 → REGULAR (주황 뱃지)
//   5회~  → VIP     (금색 뱃지)
//
// pos.service.ts 의 알림 발송 로직(특정 회차 도달 시 ORDER_VIP 발송)에서도
// 사용. 단일 진입점 보장 — 프론트와 백엔드가 같은 임계값을 공유.
export function resolveLoyaltyRank(
  visitCount: number,
): 'NORMAL' | 'REGULAR' | 'VIP' {
  if (visitCount >= 5) return 'VIP';
  if (visitCount >= 3) return 'REGULAR';
  return 'NORMAL';
}

// ══════════════════════════════════════════════════════════
// 단골 알림 발송 정책 (2026-05-31 추가)
// ══════════════════════════════════════════════════════════
//
// pos.service.ts updateOrderStatus 가 COMPLETED 분기에서 호출.
// "매 5의 배수" 회차 도달 시 ORDER_VIP 알림(축하 톤).
//   - 5회: VIP 승급 (최초 VIP 도달)
//   - 10/15/20/...회: 누적 단골 축하 milestone
// 1~4회는 클라이언트 토스트로만 처리(서버 알림 X — 노이즈 방지).
export function shouldSendLoyaltyMilestone(visitCount: number): boolean {
  if (visitCount < 5) return false;
  return visitCount % 5 === 0;
}

// ── Haversine 거리 계산 (m) ─────────────────────────────
// recommendations.service.ts 동일 로직.
function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371000; // 지구 반지름 (m)
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}
