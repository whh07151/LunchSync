import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: LSPOS 예약/웨이팅 모듈 비즈니스 로직
//
// 책임:
//   1) 식당별 예약/웨이팅 목록 CRUD
//   2) 상태 전이: OPEN → SEATED / CANCELLED
//
// 마이그레이션: 2026-05-14-add-pos-reservations.sql
// ══════════════════════════════════════════════════════════

export type ReservationKind = 'WAITING' | 'RESERVATION';
export type ReservationStatus = 'OPEN' | 'SEATED' | 'CANCELLED';

export interface ReservationDto {
  id: string;
  restaurantId: string;
  kind: ReservationKind;
  customerName: string;
  partySize: number;
  scheduledAt: string | null;
  note: string | null;
  status: ReservationStatus;
  createdAt: string;
}

export interface CreateReservationDto {
  kind: ReservationKind;
  customerName: string;
  partySize: number;
  scheduledAt?: string | null;
  note?: string;
}

@Injectable()
export class PosReservationsService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── 식당별 목록 ───────────────────────────────────────
  async list(restaurantId: string): Promise<ReservationDto[]> {
    const { data, error } = await this.supabase.client
      .from('pos_reservations')
      .select(
        'id, restaurant_id, kind, customer_name, party_size, scheduled_at, note, status, created_at',
      )
      .eq('restaurant_id', restaurantId)
      .order('created_at', { ascending: false })
      .limit(200);

    if (error) {
      throw new Error(`예약 조회 실패: ${error.message}`);
    }
    return (data ?? []).map((r) => this.toDto(r));
  }

  // ── 추가 ──────────────────────────────────────────────
  async add(
    restaurantId: string,
    dto: CreateReservationDto,
  ): Promise<ReservationDto> {
    const { data, error } = await this.supabase.client
      .from('pos_reservations')
      .insert({
        restaurant_id: restaurantId,
        kind: dto.kind,
        customer_name: dto.customerName,
        party_size: dto.partySize,
        scheduled_at: dto.scheduledAt ?? null,
        note: dto.note ?? null,
        status: 'OPEN',
      })
      .select(
        'id, restaurant_id, kind, customer_name, party_size, scheduled_at, note, status, created_at',
      )
      .single();

    if (error || !data) {
      throw new Error(`예약 추가 실패: ${error?.message}`);
    }
    return this.toDto(data);
  }

  // ── 상태 변경 ─────────────────────────────────────────
  async updateStatus(
    id: string,
    status: ReservationStatus,
  ): Promise<ReservationDto> {
    const { data, error } = await this.supabase.client
      .from('pos_reservations')
      .update({ status, updated_at: new Date().toISOString() })
      .eq('id', id)
      .select(
        'id, restaurant_id, kind, customer_name, party_size, scheduled_at, note, status, created_at',
      )
      .single();

    if (error || !data) {
      throw new NotFoundException('예약을 찾을 수 없습니다.');
    }
    return this.toDto(data);
  }

  // ── 삭제 ──────────────────────────────────────────────
  async remove(id: string): Promise<{ id: string; deleted: boolean }> {
    const { error } = await this.supabase.client
      .from('pos_reservations')
      .delete()
      .eq('id', id);

    if (error) {
      throw new Error(`예약 삭제 실패: ${error.message}`);
    }
    return { id, deleted: true };
  }

  // ── 내부 변환 ─────────────────────────────────────────
  private toDto(row: Record<string, unknown>): ReservationDto {
    return {
      id: row.id as string,
      restaurantId: row.restaurant_id as string,
      kind: row.kind as ReservationKind,
      customerName: row.customer_name as string,
      partySize: row.party_size as number,
      scheduledAt: (row.scheduled_at as string | null) ?? null,
      note: (row.note as string | null) ?? null,
      status: row.status as ReservationStatus,
      createdAt: row.created_at as string,
    };
  }
}
