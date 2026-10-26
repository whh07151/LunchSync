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

type OwnedRestaurantRow = Omit<RestaurantResult, 'imageUrl' | 'posToken'> & {
  image_url: string | null;
  owner_user_id: string | null;
};

@Injectable()
export class PosRestaurantsService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwt: JwtService,
  ) {}

  async create(
    ownerUserId: string,
    dto: CreateRestaurantDto,
  ): Promise<RestaurantResult> {
    const existing = await this.findOwnedRestaurant(ownerUserId);

    if (existing) {
      throw new ConflictException(
        '이미 등록된 식당이 있습니다. 기존 식당을 확인해 주세요.',
      );
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
      throw new Error('POS_RESTAURANT_CREATE_FAILED');
    }

    const posToken = this.issueOwnerPosToken(data.id, ownerUserId);

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
    const data = await this.findOwnedRestaurant(ownerUserId);
    if (!data) throw new NotFoundException('등록된 식당이 없습니다.');

    const posToken = this.issueOwnerPosToken(data.id, ownerUserId);

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

  private async findOwnedRestaurant(
    ownerUserId: string,
  ): Promise<OwnedRestaurantRow | null> {
    const columns =
      'id, name, category, address, lat, lng, image_url, owner_user_id';
    const { data: canonical, error: canonicalError } =
      await this.supabase.client
        .from('restaurants')
        .select(columns)
        .eq('owner_user_id', ownerUserId)
        .maybeSingle();

    if (canonicalError) {
      throw new Error('POS_RESTAURANT_LOOKUP_FAILED');
    }
    if (canonical) return canonical as OwnedRestaurantRow;

    const { data: owner, error: ownerError } = await this.supabase.client
      .from('users')
      .select('restaurant_id')
      .eq('id', ownerUserId)
      .maybeSingle();
    if (ownerError) throw new Error('POS_RESTAURANT_OWNER_LOOKUP_FAILED');
    if (!owner?.restaurant_id) return null;

    const { data: legacy, error: legacyError } = await this.supabase.client
      .from('restaurants')
      .select(columns)
      .eq('id', owner.restaurant_id)
      .maybeSingle();
    if (legacyError) throw new Error('POS_RESTAURANT_LEGACY_LOOKUP_FAILED');
    if (!legacy) return null;
    if (legacy.owner_user_id != null && legacy.owner_user_id !== ownerUserId) {
      return null;
    }

    if (legacy.owner_user_id == null) {
      const { data: competingLegacyOwner, error: legacyMappingError } =
        await this.supabase.client
          .from('users')
          .select('id')
          .eq('restaurant_id', legacy.id)
          .neq('id', ownerUserId)
          .limit(1)
          .maybeSingle();
      if (legacyMappingError) {
        throw new Error(
          `매장 소유권 매핑 조회 실패: ${legacyMappingError.message}`,
        );
      }
      if (competingLegacyOwner) {
        throw new ConflictException(
          '여러 계정에 연결된 기존 매장입니다. 관리자에게 소유권 정리를 요청해주세요.',
        );
      }

      // legacy users.restaurant_id 매핑을 토큰 발급 전에 canonical 소유권으로
      // 원자 승격한다. 그래야 이후 POS 요청이 현재 owner/status를 재검증할 수 있다.
      const { data: claimed, error: claimError } = await this.supabase.client
        .from('restaurants')
        .update({ owner_user_id: ownerUserId })
        .eq('id', legacy.id)
        .is('owner_user_id', null)
        .select(columns)
        .maybeSingle();
      if (claimError) {
        throw new Error('POS_RESTAURANT_OWNERSHIP_SYNC_FAILED');
      }
      if (!claimed) {
        // 다른 요청이 먼저 소유권을 정했다면 잘못된 POS 토큰을 발급하지 않는다.
        return null;
      }
      return claimed as OwnedRestaurantRow;
    }

    return legacy as OwnedRestaurantRow;
  }

  private issueOwnerPosToken(
    restaurantId: string,
    ownerUserId: string,
  ): string {
    return this.jwt.sign(
      {
        sub: restaurantId,
        type: 'POS',
        ownerUserId,
        authMode: 'OWNER',
      },
      { expiresIn: '8h' },
    );
  }
}
