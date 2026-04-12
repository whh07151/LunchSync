import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 유저 관련 비즈니스 로직
//
// 담당 엔드포인트:
//   GET  /users/me  — 내 프로필 조회
//   PATCH /users/me — 프로필/조건 수정 (온보딩 CU-03/CU-05 완료 시 호출)
// ══════════════════════════════════════════════════════════

// PATCH /users/me 요청 바디 타입
export interface UpdateUserDto {
  name?: string;
  org?: string;
  profileImage?: string;
  radius?: string;
  budget?: number;
  speed?: string;
  allergies?: string[];
  dislikes?: string[];
}

@Injectable()
export class UsersService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── GET /users/me ─────────────────────────────────────
  // JWT에서 추출한 userId로 내 프로필 조회
  async getMe(userId: string) {
    const { data, error } = await this.supabase.client
      .from('users')
      .select('id, name, org, profile_image, radius, budget, speed, role, allergies, dislikes')
      .eq('id', userId)
      .single();

    if (error || !data) {
      throw new NotFoundException('유저를 찾을 수 없습니다.');
    }

    // DB snake_case → 응답 camelCase 변환
    return {
      id: data.id,
      name: data.name,
      org: data.org,
      profileImage: data.profile_image,
      radius: data.radius,
      budget: data.budget,
      speed: data.speed,
      role: data.role,
      allergies: data.allergies ?? [],
      dislikes: data.dislikes ?? [],
    };
  }

  // ── PATCH /users/me ───────────────────────────────────
  // 온보딩(CU-03/CU-05) 완료 시 이름/소속/반경/예산/속도 저장
  // JWT에서 userId 추출 → 클라이언트는 ID 전달 불필요
  async updateMe(userId: string, dto: UpdateUserDto) {
    // camelCase → snake_case 변환 후 Supabase에 저장
    const updateData: Record<string, unknown> = {};
    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.org !== undefined) updateData.org = dto.org;
    if (dto.profileImage !== undefined) updateData.profile_image = dto.profileImage;
    if (dto.radius !== undefined) updateData.radius = dto.radius;
    if (dto.budget !== undefined) updateData.budget = dto.budget;
    if (dto.speed !== undefined) updateData.speed = dto.speed;
    if (dto.allergies !== undefined) updateData.allergies = dto.allergies;
    if (dto.dislikes !== undefined) updateData.dislikes = dto.dislikes;

    const { data, error } = await this.supabase.client
      .from('users')
      .update(updateData)
      .eq('id', userId)
      .select('id, name, org, profile_image, radius, budget, speed, allergies, dislikes')
      .single();

    if (error || !data) {
      throw new Error(`프로필 수정 실패: ${error?.message}`);
    }

    return {
      id: data.id,
      name: data.name,
      org: data.org,
      profileImage: data.profile_image,
      radius: data.radius,
      budget: data.budget,
      speed: data.speed,
      allergies: data.allergies ?? [],
      dislikes: data.dislikes ?? [],
    };
  }
}
