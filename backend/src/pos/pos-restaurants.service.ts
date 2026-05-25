import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장 계정 기반 식당 등록/조회 비즈니스 로직
//
// 엔드포인트 (PosRestaurantsController):
//   POST /api/pos/restaurants    — 사장이 식당 등록 (USER JWT 필수)
//   GET  /api/pos/my-restaurant  — 내 식당 조회   (USER JWT 필수)
//
// 설계 원칙:
//   - 사장 1명 = 식당 1개 (1:1 제약, ConflictException 으로 강제)
//   - 등록 즉시 POS JWT 발급 → LSPOS 가 바로 대시보드 진입 가능
//   - owner_user_id 컬럼으로 사장 계정 ↔ 식당 연결
// ══════════════════════════════════════════════════════════

export interface CreateRestaurantDto {
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  priceRange?: number; // DB: restaurants.price_range = integer
  imageUrl?: string;
}

export interface RestaurantResult {
  id: string;
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  imageUrl: string | null;
  posToken: string;
}

@Injectable()
export class PosRestaurantsService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwt: JwtService,
  ) {}

  async create(ownerUserId: string, dto: CreateRestaurantDto): Promise<RestaurantResult> {
    const { data: existing } = await this.supabase.client
      .from('restaurants')
      .select('id')
      .eq('owner_user_id', ownerUserId)
      .maybeSingle();

    if (existing) {
      throw new ConflictException('이미 등록된 식당이 있습니다. 기존 식당을 확인해 주세요.');
    }

    const { data, error } = await this.supabase.client
      .from('restaurants')
      .insert({
        name: dto.name,
        category: dto.category,
        address: dto.address,
        lat: dto.lat,
        lng: dto.lng,
        price_range: dto.priceRange ?? null,
        image_url: dto.imageUrl ?? null,
        owner_user_id: ownerUserId,
      })
      .select('id, name, category, address, lat, lng, image_url')
      .single();

    if (error || !data) {
      throw new Error(`식당 생성 실패: ${error?.message}`);
    }

    const posToken = this.jwt.sign({ sub: data.id, type: 'POS' });

    return {
      id: data.id,
      name: data.name,
      category: data.category,
      address: data.address,
      lat: data.lat,
      lng: data.lng,
      imageUrl: data.image_url,
      posToken,
    };
  }

  async getMyRestaurant(ownerUserId: string): Promise<RestaurantResult> {
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, address, lat, lng, image_url')
      .eq('owner_user_id', ownerUserId)
      .maybeSingle();

    if (error) throw new Error(`식당 조회 실패: ${error.message}`);
    if (!data) throw new NotFoundException('등록된 식당이 없습니다.');

    const posToken = this.jwt.sign({ sub: data.id, type: 'POS' });

    return {
      id: data.id,
      name: data.name,
      category: data.category,
      address: data.address,
      lat: data.lat,
      lng: data.lng,
      imageUrl: data.image_url,
      posToken,
    };
  }
}
