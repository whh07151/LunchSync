import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

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
    let qb = this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, created_at');

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
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      imageUrl: r.image_url,
      createdAt: r.created_at,
    }));
  }

  // ── GET /restaurants/:id ──────────────────────────────
  async getRestaurantById(id: string) {
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, created_at')
      .eq('id', id)
      .single();

    if (error || !data) {
      throw new NotFoundException('식당을 찾을 수 없습니다.');
    }

    return {
      id: data.id,
      name: data.name,
      category: data.category,
      priceRange: data.price_range,
      address: data.address,
      lat: data.lat,
      lng: data.lng,
      imageUrl: data.image_url,
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

    const menus = (data ?? []).map((m) => ({
      id: m.id,
      name: m.name,
      price: m.price,
      category: m.category,
      description: m.description,
      imageUrl: m.image_url,
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
