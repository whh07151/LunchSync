import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 사장/POS 메뉴 관리 비즈니스 로직 (CRUD)
//
// 사용처:
//   - 사장 홈(owner_home_screen) → 메뉴 관리 탭
//   - LSPOS /menu 페이지 (현재 localStorage → 본 API 로 점진 교체)
//
// menu_items 컬럼 (2026-05-12 마이그레이션 후):
//   id, restaurant_id, name, price, category, description, image_url, is_available
//   prep_time_minutes (2026-05-16 추가, 배민 패턴 — 손님 ETA 계산용)
// ══════════════════════════════════════════════════════════

export interface CreateMenuDto {
  name: string;
  price: number;
  category?: string;
  description?: string;
  imageUrl?: string;
  // 2026-05-16 배민 패턴 — 예상 조리 시간 (분, 1~120, 미지정 시 DB DEFAULT 15)
  prepTimeMinutes?: number;
}

export interface UpdateMenuDto {
  name?: string;
  price?: number;
  category?: string;
  description?: string;
  imageUrl?: string;
  isAvailable?: boolean;
  prepTimeMinutes?: number;
}

@Injectable()
export class PosMenusService {
  constructor(private readonly supabase: SupabaseService) {}

  /// 권한 검증용: menuId → restaurant_id 사전 조회.
  /// 컨트롤러가 update/delete 전에 권한 일치를 확인하기 위함.
  async getRestaurantIdByMenuId(menuId: string): Promise<string> {
    const { data, error } = await this.supabase.client
      .from('menu_items')
      .select('restaurant_id')
      .eq('id', menuId)
      .single();
    if (error || !data?.restaurant_id) {
      throw new NotFoundException('메뉴를 찾을 수 없습니다.');
    }
    return data.restaurant_id as string;
  }

  /// 식당의 메뉴 전체 목록 — 품절 포함 (사장 화면이 품절 토글하기 위해 모두 필요).
  /// 2026-05-16: prep_time_minutes 응답 포함 (배민 패턴 ETA 계산용)
  async list(restaurantId: string) {
    const { data, error } = await this.supabase.client
      .from('menu_items')
      .select(
        'id, name, price, category, description, image_url, is_available, restaurant_id, prep_time_minutes',
      )
      .eq('restaurant_id', restaurantId)
      .order('category')
      .order('price');

    if (error) {
      throw new Error(`메뉴 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((m) => ({
      id: m.id,
      restaurantId: m.restaurant_id,
      name: m.name,
      price: m.price,
      category: m.category,
      description: m.description,
      imageUrl: m.image_url,
      isAvailable: m.is_available ?? true,
      prepTimeMinutes: m.prep_time_minutes ?? 15,
    }));
  }

  /// 메뉴 신규 추가 — restaurant_id, name, price 필수. category 미지정 시 '기타'.
  /// 2026-05-16: prep_time_minutes 입력 시 검증 (1~120), 미지정 시 DB DEFAULT 15
  async create(restaurantId: string, dto: CreateMenuDto) {
    if (dto.prepTimeMinutes !== undefined) {
      this.validatePrepTime(dto.prepTimeMinutes);
    }
    const insert: Record<string, unknown> = {
      restaurant_id: restaurantId,
      name: dto.name,
      price: dto.price,
      category: dto.category ?? '기타',
      description: dto.description ?? null,
      image_url: dto.imageUrl ?? null,
      is_available: true,
    };
    if (dto.prepTimeMinutes !== undefined) {
      insert.prep_time_minutes = dto.prepTimeMinutes;
    }

    const { data, error } = await this.supabase.client
      .from('menu_items')
      .insert(insert)
      .select(
        'id, name, price, category, description, image_url, is_available, restaurant_id, prep_time_minutes',
      )
      .single();

    if (error || !data) {
      throw new Error(`메뉴 추가 실패: ${error?.message}`);
    }

    return this.toResponse(data);
  }

  /// 메뉴 수정 — 부분 수정. isAvailable 토글 포함.
  /// 2026-05-16: prep_time_minutes 수정 가능 (1~120 검증)
  async update(menuId: string, dto: UpdateMenuDto) {
    const patch: Record<string, unknown> = {};
    if (dto.name !== undefined) patch.name = dto.name;
    if (dto.price !== undefined) patch.price = dto.price;
    if (dto.category !== undefined) patch.category = dto.category;
    if (dto.description !== undefined) patch.description = dto.description;
    if (dto.imageUrl !== undefined) patch.image_url = dto.imageUrl;
    if (dto.isAvailable !== undefined) patch.is_available = dto.isAvailable;
    if (dto.prepTimeMinutes !== undefined) {
      this.validatePrepTime(dto.prepTimeMinutes);
      patch.prep_time_minutes = dto.prepTimeMinutes;
    }

    if (Object.keys(patch).length === 0) {
      throw new Error('수정할 항목이 없습니다.');
    }

    const { data, error } = await this.supabase.client
      .from('menu_items')
      .update(patch)
      .eq('id', menuId)
      .select(
        'id, name, price, category, description, image_url, is_available, restaurant_id, prep_time_minutes',
      )
      .single();

    if (error || !data) {
      throw new NotFoundException('메뉴를 찾을 수 없습니다.');
    }

    return this.toResponse(data);
  }

  /// 메뉴 삭제 — 실제 DELETE. order_items 가 FK 로 참조 중이면 RESTRICT 오류.
  /// 그 경우 사장 화면에서 "품절 토글" 사용을 권장.
  async delete(menuId: string) {
    const { error } = await this.supabase.client
      .from('menu_items')
      .delete()
      .eq('id', menuId);

    if (error) {
      // FK 위반 등 — 화면이 적절히 안내하도록 메시지 그대로 위로
      throw new Error(
        '메뉴 삭제에 실패했어요. 이미 주문에 사용된 메뉴는 "품절"로 변경해 주세요.',
      );
    }

    return { id: menuId, deleted: true };
  }

  private toResponse(data: any) {
    return {
      id: data.id,
      restaurantId: data.restaurant_id,
      name: data.name,
      price: data.price,
      category: data.category,
      description: data.description,
      imageUrl: data.image_url,
      isAvailable: data.is_available ?? true,
      prepTimeMinutes: data.prep_time_minutes ?? 15,
    };
  }

  // 2026-05-16: prep_time_minutes 범위 검증 (DB CHECK 와 동일)
  private validatePrepTime(value: number): void {
    if (!Number.isInteger(value) || value < 1 || value > 120) {
      throw new Error('예상 조리 시간은 1~120 분 사이의 정수여야 합니다.');
    }
  }
}
