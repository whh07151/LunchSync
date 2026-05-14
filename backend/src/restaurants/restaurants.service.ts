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
    let qb = this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, rating, created_at');

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
      createdAt: r.created_at,
    }));
  }

  // ── GET /restaurants/:id ──────────────────────────────
  async getRestaurantById(id: string) {
    // 2026-05-14 rating 컬럼 select 추가 — 상세 화면에서도 평점 표시.
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, rating, created_at')
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
