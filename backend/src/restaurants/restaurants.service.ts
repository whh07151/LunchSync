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
}

@Injectable()
export class RestaurantsService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── GET /restaurants ──────────────────────────────────
  // 필터 조건으로 식당 목록 조회
  async getRestaurants(query: GetRestaurantsQuery) {
    let qb = this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, created_at');

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

    return (data ?? []).map((r) => ({
      id: r.id,
      name: r.name,
      category: r.category,
      priceRange: r.price_range,
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      createdAt: r.created_at,
    }));
  }

  // ── GET /restaurants/:id ──────────────────────────────
  async getRestaurantById(id: string) {
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, created_at')
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
      createdAt: data.created_at,
    };
  }

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
