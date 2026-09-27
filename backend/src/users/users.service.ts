import {
  BadRequestException,
  ConflictException,
  Injectable,
  InternalServerErrorException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
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

// 2026-05-31 CU-04 — PATCH /users/me/preferences 요청 바디 타입.
// 추천 엔진이 직접 읽는 구조화 데이터.
export interface UpdatePreferencesDto {
  tasteTags?: string[]; // 좋아하는 맛 태그
  allergens?: string[]; // 알레르기 식재료 (후보군 제외)
  dislikedCategories?: string[]; // 비선호 카테고리 (점수 감점/제외)
}

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(private readonly supabase: SupabaseService) {}

  // ── GET /users/me ─────────────────────────────────────
  // JWT에서 추출한 userId로 내 프로필 조회.
  // 2026-05-31 CU-04 — taste_tags / allergens / disliked_categories 컬럼 동기 노출.
  async getMe(userId: string) {
    const { data, error } = await this.supabase.client
      .from('users')
      .select(
        'id, name, org, profile_image, radius, budget, speed, role, status, auth_provider, email, phone_number, business_name, business_number, restaurant_id, allergies, dislikes, taste_tags, allergens, disliked_categories',
      )
      .eq('id', userId)
      .single();

    if (error || !data) {
      throw new NotFoundException('유저를 찾을 수 없습니다.');
    }

    // restaurants.owner_user_id가 점주 소유권의 기준이다. 신규 등록 경로는
    // 이 컬럼을 즉시 기록하므로 users.restaurant_id가 아직 NULL이어도 앱이
    // 정상 매장 ID를 받는다. canonical 매핑이 없는 기존 데이터만 legacy 값을 쓴다.
    let restaurantId = data.restaurant_id as string | null;
    if (data.role === 'OWNER') {
      const { data: ownedRestaurant, error: restaurantError } =
        await this.supabase.client
          .from('restaurants')
          .select('id')
          .eq('owner_user_id', userId)
          .maybeSingle();

      if (restaurantError) {
        this.logger.error('USER_OWNER_MAPPING_LOOKUP_FAILED');
        throw new InternalServerErrorException(
          '매장 연결 정보를 확인할 수 없습니다.',
        );
      }
      restaurantId = ownedRestaurant?.id ?? restaurantId;
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
      // canonical owner_user_id를 우선하고, 기존 users.restaurant_id를 보조로 사용.
      restaurantId,
      allergies: data.allergies ?? [],
      dislikes: data.dislikes ?? [],
      // 2026-05-31 CU-04 — 추천 엔진이 읽는 구조화 취향 데이터
      tasteTags: data.taste_tags ?? [],
      allergens: data.allergens ?? [],
      dislikedCategories: data.disliked_categories ?? [],
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
    if (dto.profileImage !== undefined)
      updateData.profile_image = dto.profileImage;
    if (dto.radius !== undefined) updateData.radius = dto.radius;
    if (dto.budget !== undefined) updateData.budget = dto.budget;
    if (dto.speed !== undefined) updateData.speed = dto.speed;
    if (dto.allergies !== undefined) updateData.allergies = dto.allergies;
    if (dto.dislikes !== undefined) updateData.dislikes = dto.dislikes;
    // OWNER 전용 — DB 컬럼명도 snake_case
    if (dto.businessName !== undefined)
      updateData.business_name = dto.businessName;
    if (dto.businessNumber !== undefined)
      updateData.business_number = dto.businessNumber;

    const { data, error } = await this.supabase.client
      .from('users')
      .update(updateData)
      .eq('id', userId)
      .select(
        'id, name, org, profile_image, radius, budget, speed, allergies, dislikes, business_name, business_number',
      )
      .single();

    if (error || !data) {
      throw new Error('USER_PROFILE_UPDATE_FAILED');
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

  // ── PATCH /users/me/preferences ──────────────────────────
  // 2026-05-31 CU-04 — 손님 취향/알레르기/비선호 카테고리 일괄 저장.
  //
  // 정책:
  //   - 세 필드 모두 선택적 (undefined 면 미변경)
  //   - 빈 배열 [] 은 "모두 해제" 의미 — DB 에 빈 배열로 그대로 저장
  //   - DB 컬럼명은 snake_case (taste_tags / allergens / disliked_categories)
  //
  // 응답:
  //   { tasteTags, allergens, dislikedCategories } — 저장된 최종값.
  //   프론트는 이 값으로 자신의 캐시를 동기화.
  async updatePreferences(
    userId: string,
    dto: UpdatePreferencesDto,
  ): Promise<{
    tasteTags: string[];
    allergens: string[];
    dislikedCategories: string[];
  }> {
    // camelCase → snake_case 매핑. undefined 필드는 보내지 않음.
    const updateData: Record<string, unknown> = {};
    if (dto.tasteTags !== undefined) updateData.taste_tags = dto.tasteTags;
    if (dto.allergens !== undefined) updateData.allergens = dto.allergens;
    if (dto.dislikedCategories !== undefined) {
      updateData.disliked_categories = dto.dislikedCategories;
    }

    // 변경 대상이 하나도 없으면 DB 호출 생략 — 현재값 그대로 반환.
    // (불필요한 update 이벤트로 다른 구독자가 깨어나지 않도록)
    if (Object.keys(updateData).length === 0) {
      const me = await this.getMe(userId);
      return {
        tasteTags: me.tasteTags,
        allergens: me.allergens,
        dislikedCategories: me.dislikedCategories,
      };
    }

    const { data, error } = await this.supabase.client
      .from('users')
      .update(updateData)
      .eq('id', userId)
      .select('taste_tags, allergens, disliked_categories')
      .single();

    if (error || !data) {
      this.logger.error('USER_PREFERENCE_PERSIST_FAILED');
      throw new InternalServerErrorException('취향 설정을 저장하지 못했어요.');
    }

    return {
      tasteTags: data.taste_tags ?? [],
      allergens: data.allergens ?? [],
      dislikedCategories: data.disliked_categories ?? [],
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
      throw new Error('USER_FCM_TOKEN_PERSIST_FAILED');
    }
  }

  // ══════════════════════════════════════════════════════════
  // 즐겨찾기 (배민 패턴 — 2026-05-15 발전 로드맵)
  //
  // DB: users.favorites JSONB DEFAULT '[]'::jsonb (식당 ID 배열)
  // 정책:
  //   - 최대 100개 (한도 초과 시 409 Conflict)
  //   - 중복 추가 → 멱등 (이미 있으면 추가 안 함)
  //   - 추가 순 정렬 — 가장 최근이 배열 마지막
  // ══════════════════════════════════════════════════════════

  // ── POST /users/me/favorites ─────────────────────────────
  // 식당 ID 를 즐겨찾기 배열에 추가.
  async addFavorite(userId: string, restaurantId: string): Promise<string[]> {
    if (!restaurantId || restaurantId.trim().length === 0) {
      throw new BadRequestException('식당 ID 가 비어있어요.');
    }

    // 1) 현재 favorites 조회 (JSONB 그대로)
    const { data: user, error: getError } = await this.supabase.client
      .from('users')
      .select('favorites')
      .eq('id', userId)
      .single();

    if (getError || !user) {
      throw new NotFoundException('사용자를 찾을 수 없어요.');
    }

    const current: string[] = Array.isArray(user.favorites)
      ? (user.favorites as string[])
      : [];

    if (current.includes(restaurantId)) {
      // 멱등 — 이미 있으면 그대로 반환
      return current;
    }

    if (current.length >= 100) {
      throw new ConflictException(
        '즐겨찾기는 최대 100개까지 등록할 수 있어요.',
      );
    }

    const next = [...current, restaurantId];

    // 2) 업데이트
    const { error: updateError } = await this.supabase.client
      .from('users')
      .update({ favorites: next })
      .eq('id', userId);

    if (updateError) {
      this.logger.error('USER_FAVORITE_ADD_PERSIST_FAILED');
      throw new InternalServerErrorException('즐겨찾기를 추가하지 못했어요.');
    }

    return next;
  }

  // ── DELETE /users/me/favorites/:restaurantId ─────────────
  // 즐겨찾기 배열에서 해당 식당 ID 제거 (멱등).
  async removeFavorite(
    userId: string,
    restaurantId: string,
  ): Promise<string[]> {
    const { data: user, error: getError } = await this.supabase.client
      .from('users')
      .select('favorites')
      .eq('id', userId)
      .single();

    if (getError || !user) {
      throw new NotFoundException('사용자를 찾을 수 없어요.');
    }

    const current: string[] = Array.isArray(user.favorites)
      ? (user.favorites as string[])
      : [];

    const next = current.filter((id) => id !== restaurantId);

    if (next.length === current.length) {
      // 멱등 — 이미 없는 경우 그대로 반환
      return next;
    }

    const { error: updateError } = await this.supabase.client
      .from('users')
      .update({ favorites: next })
      .eq('id', userId);

    if (updateError) {
      this.logger.error('USER_FAVORITE_REMOVE_PERSIST_FAILED');
      throw new InternalServerErrorException('즐겨찾기를 제거하지 못했어요.');
    }

    return next;
  }

  // ── GET /users/me/favorites ──────────────────────────────
  // 내 즐겨찾기 식당 목록 (식당 정보 join).
  // restaurants 의 image_url/rating 등 모든 필드 포함.
  async listFavorites(userId: string): Promise<
    Array<{
      id: string;
      name: string;
      category: string;
      address: string | null;
      imageUrl: string | null;
      rating: number | null;
    }>
  > {
    const { data: user, error: getError } = await this.supabase.client
      .from('users')
      .select('favorites')
      .eq('id', userId)
      .single();

    if (getError || !user) {
      throw new NotFoundException('사용자를 찾을 수 없어요.');
    }

    const ids: string[] = Array.isArray(user.favorites)
      ? (user.favorites as string[])
      : [];

    if (ids.length === 0) return [];

    const { data: restaurants, error: restError } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, address, image_url, rating')
      .in('id', ids);

    if (restError) {
      this.logger.error('USER_FAVORITE_RESTAURANT_LOOKUP_FAILED');
      throw new InternalServerErrorException(
        '즐겨찾기 식당을 불러오지 못했어요.',
      );
    }

    // 추가 순서 보존 (ids 배열 순서대로) — 가장 최근이 마지막
    const byId = new Map((restaurants ?? []).map((r: any) => [r.id, r]));

    return ids
      .map((id) => byId.get(id))
      .filter(Boolean)
      .map((r: any) => ({
        id: r.id,
        name: r.name ?? '식당',
        category: r.category ?? '기타',
        address: r.address ?? null,
        imageUrl: r.image_url ?? null,
        rating: r.rating != null ? Number(r.rating) : null,
      }));
  }
}
