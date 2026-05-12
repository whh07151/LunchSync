import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/LSPOS 좌석 모듈 비즈니스 로직
//
// 책임:
//   1) 식당별 좌석 목록 CRUD
//   2) 좌석 점유/해제, 좌석 항목 추가/감소/제거
//   3) JSONB items 컬럼에 [{ menuId, name, price, quantity, addedAt }] 저장
//
// 마이그레이션: 2026-05-14-add-pos-tables.sql
// ══════════════════════════════════════════════════════════

// 좌석 응답 DTO — LSPOS 의 Seat 타입과 1:1 매핑
export interface SeatItemDto {
  menuId: string;
  name: string;
  price: number;
  quantity: number;
  addedAt: string;
}

export interface SeatDto {
  id: string;
  restaurantId: string;
  label: string;
  status: 'empty' | 'occupied';
  startedAt: string | null;
  items: SeatItemDto[];
  sortOrder: number;
}

// 좌석 생성/수정 입력 타입
export interface UpsertSeatDto {
  label?: string;
  status?: 'empty' | 'occupied';
  startedAt?: string | null;
  items?: SeatItemDto[];
  sortOrder?: number;
}

@Injectable()
export class PosSeatsService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── 권한 검증용: seatId → restaurant_id 사전 조회 ──────
  // 컨트롤러가 update/remove 전에 권한 일치를 확인하기 위함.
  async getRestaurantIdBySeatId(seatId: string): Promise<string> {
    const { data, error } = await this.supabase.client
      .from('pos_seats')
      .select('restaurant_id')
      .eq('id', seatId)
      .single();
    if (error || !data?.restaurant_id) {
      throw new NotFoundException('좌석을 찾을 수 없습니다.');
    }
    return data.restaurant_id as string;
  }

  // ── 식당별 좌석 목록 ──────────────────────────────────
  async listSeats(restaurantId: string): Promise<SeatDto[]> {
    const { data, error } = await this.supabase.client
      .from('pos_seats')
      .select('id, restaurant_id, label, status, started_at, items, sort_order')
      .eq('restaurant_id', restaurantId)
      .order('sort_order', { ascending: true });

    if (error) {
      throw new Error(`좌석 조회 실패: ${error.message}`);
    }

    return (data ?? []).map((s) => this.toDto(s));
  }

  // ── 좌석 추가 ─────────────────────────────────────────
  // label/sortOrder 가 명시되지 않으면 현재 최대 + 1 로 자동 할당.
  async addSeat(restaurantId: string, label?: string): Promise<SeatDto> {
    // 현재 최대 sort_order 조회 (단순 처리 — 정확성 위해 추후 트랜잭션 가능)
    const existing = await this.listSeats(restaurantId);
    const nextOrder = existing.length;
    const finalLabel = label ?? `${nextOrder + 1}번`;

    const { data, error } = await this.supabase.client
      .from('pos_seats')
      .insert({
        restaurant_id: restaurantId,
        label: finalLabel,
        status: 'empty',
        items: [],
        sort_order: nextOrder,
      })
      .select('id, restaurant_id, label, status, started_at, items, sort_order')
      .single();

    if (error || !data) {
      throw new Error(`좌석 추가 실패: ${error?.message}`);
    }
    return this.toDto(data);
  }

  // ── 좌석 갱신 ─────────────────────────────────────────
  // items 추가/감소, 점유/해제, 라벨 변경 등 모든 변경을 단일 PATCH 로 통합.
  async updateSeat(seatId: string, dto: UpsertSeatDto): Promise<SeatDto> {
    const payload: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (dto.label !== undefined) payload.label = dto.label;
    if (dto.status !== undefined) payload.status = dto.status;
    if (dto.startedAt !== undefined) payload.started_at = dto.startedAt;
    if (dto.items !== undefined) payload.items = dto.items;
    if (dto.sortOrder !== undefined) payload.sort_order = dto.sortOrder;

    const { data, error } = await this.supabase.client
      .from('pos_seats')
      .update(payload)
      .eq('id', seatId)
      .select('id, restaurant_id, label, status, started_at, items, sort_order')
      .single();

    if (error || !data) {
      throw new NotFoundException('좌석을 찾을 수 없습니다.');
    }
    return this.toDto(data);
  }

  // ── 좌석 삭제 ─────────────────────────────────────────
  // 점유 중(occupied)인 좌석은 삭제 거부 — 안전성.
  async removeSeat(seatId: string): Promise<{ id: string; deleted: boolean }> {
    const { data: target } = await this.supabase.client
      .from('pos_seats')
      .select('id, status')
      .eq('id', seatId)
      .single();

    if (!target) {
      throw new NotFoundException('좌석을 찾을 수 없습니다.');
    }
    if (target.status === 'occupied') {
      throw new Error('점유 중인 좌석은 삭제할 수 없습니다.');
    }

    const { error } = await this.supabase.client
      .from('pos_seats')
      .delete()
      .eq('id', seatId);

    if (error) {
      throw new Error(`좌석 삭제 실패: ${error.message}`);
    }
    return { id: seatId, deleted: true };
  }

  // ── 내부: snake_case → camelCase 변환 ─────────────────
  private toDto(row: Record<string, unknown>): SeatDto {
    return {
      id: row.id as string,
      restaurantId: row.restaurant_id as string,
      label: row.label as string,
      status: row.status as 'empty' | 'occupied',
      startedAt: (row.started_at as string | null) ?? null,
      items: (row.items as SeatItemDto[] | null) ?? [],
      sortOrder: (row.sort_order as number) ?? 0,
    };
  }
}
