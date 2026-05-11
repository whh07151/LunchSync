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
  // OWNER 전용 — 사장 내정보 탭에서 상호/사업자번호 수정
  businessName?: string;
  businessNumber?: string;
}

@Injectable()
export class UsersService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── GET /users/me ─────────────────────────────────────
  // JWT에서 추출한 userId로 내 프로필 조회
  async getMe(userId: string) {
    const { data, error } = await this.supabase.client
      .from('users')
      .select(
        'id, name, org, profile_image, radius, budget, speed, role, status, auth_provider, email, phone_number, business_name, business_number, restaurant_id, allergies, dislikes',
      )
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
      // 회원가입/인증 결정(2026-05-07) 추가 필드
      status: data.status,
      authProvider: data.auth_provider,
      email: data.email,
      phoneNumber: data.phone_number,
      businessName: data.business_name,
      businessNumber: data.business_number,
      // OWNER ↔ 운영 식당 매핑 (NULL이면 아직 매장 미연결 — 운영자가 콘솔에서 매핑)
      restaurantId: data.restaurant_id,
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
    // OWNER 전용 — DB 컬럼명도 snake_case
    if (dto.businessName !== undefined) updateData.business_name = dto.businessName;
    if (dto.businessNumber !== undefined) updateData.business_number = dto.businessNumber;

    const { data, error } = await this.supabase.client
      .from('users')
      .update(updateData)
      .eq('id', userId)
      .select(
        'id, name, org, profile_image, radius, budget, speed, allergies, dislikes, business_name, business_number',
      )
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
      // OWNER 정보 — 사장 정보 수정 직후 상태 동기화에 사용
      businessName: data.business_name,
      businessNumber: data.business_number,
    };
  }

  // ── POST /users/me/fcm-token ────────────────────────────
  // Flutter 앱이 firebase_messaging.getToken() 으로 발급받은 토큰을 저장.
  // 동일 사용자가 단말을 바꾸면 토큰이 갱신됨 — 항상 덮어쓰기 (UPSERT 단일 행).
  //
  // 정책:
  //   - 빈 문자열 토큰은 NULL 처리 (로그아웃/푸시 비허용 대응)
  //   - 토큰이 유효한지는 FCM 측이 검증 — 백엔드는 저장만 담당
  async saveFcmToken(userId: string, token: string | null): Promise<void> {
    const normalized = token && token.length > 0 ? token : null;

    const { error } = await this.supabase.client
      .from('users')
      .update({ fcm_token: normalized })
      .eq('id', userId);

    if (error) {
      throw new Error(`FCM 토큰 저장 실패: ${error.message}`);
    }
  }
}
