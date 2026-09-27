import {
  ConflictException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: POS 단말 로그인 비즈니스 로직 (LSPOS 연동)
//
// 배경:
//   다연이 만든 LSPOS(Next.js POS 웹)는 "식당 고유번호(restaurant_id) 단일 입력"으로
//   매장 단말에 로그인하는 흐름이 명세(POS_DEV_LOG #1, pos_memo §3).
//   본 백엔드는 카카오/이메일 USER JWT 만 발급해 왔으므로 POS 단말용 JWT 발급 경로 신설.
//
// 발급 토큰 페이로드 (jwt.strategy.ts JwtPayload 와 호환):
//   { sub: restaurantId, type: 'POS' }
//
// 검증:
//   공용 PIN 방식은 비운영 환경에서 명시적으로 켠 데모에만 허용.
//   운영 환경은 매장 간 격리가 가능한 사장 계정 로그인을 사용한다.
// ══════════════════════════════════════════════════════════

@Injectable()
export class PosAuthService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  /// POS 단말 로그인 — restaurantId 검증 후 type=POS JWT 발급.
  ///
  /// PIN 검증 (2026-05-12 박검토 후 추가):
  ///   환경변수 POS_PIN 이 설정되어 있으면 pin 인자 일치 여부 확인.
  ///   미설정 시 기존 동작 유지 (하위 호환). 시연용 공통 PIN 또는
  ///   운영 전환 시 매장별 컬럼 추가로 교체.
  ///
  /// 성공 시: { accessToken, restaurantId, restaurantName }
  /// 실패 시: NotFoundException (식당 없음) / UnauthorizedException (PIN 불일치)
  async login(restaurantId: string, terminalName?: string, pin?: string) {
    // 공용 PIN은 매장별 자격 증명이 아니므로 production에서 절대 허용하지 않는다.
    // 비운영 시연도 두 환경변수를 모두 명시해야만 활성화한다.
    const nodeEnv = this.config.get<string>('NODE_ENV') ?? process.env.NODE_ENV;
    const sharedPinEnabled =
      this.config.get<string>('POS_SHARED_PIN_LOGIN_ENABLED') === 'true';
    if (nodeEnv === 'production' || !sharedPinEnabled) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'POS_SHARED_LOGIN_DISABLED',
        message: '공용 PIN 방식의 POS 로그인이 비활성 상태입니다.',
      });
    }

    const requiredPin = this.config.get<string>('POS_PIN')?.trim();
    if (!requiredPin) {
      throw new ServiceUnavailableException(
        'POS 단말 로그인이 안전하게 설정되지 않았습니다.',
      );
    }
    if (!pin || pin !== requiredPin) {
      throw new UnauthorizedException('POS 단말 PIN 이 올바르지 않습니다.');
    }

    // 자격 증명 검증 후에만 식당 존재 여부를 조회해 ID 열거를 줄인다.
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name')
      .eq('id', restaurantId)
      .single();

    if (error || !data) {
      throw new NotFoundException('등록된 식당을 찾을 수 없습니다.');
    }

    // type=POS JWT 발급 — sub 에 restaurantId 저장
    // (USER 토큰은 sub=userId, type=USER 또는 미지정. JwtStrategy.validate 가 분기)
    const accessToken = this.jwt.sign(
      {
        sub: data.id,
        type: 'POS',
        authMode: 'SHARED_PIN',
      },
      { expiresIn: '2h' },
    );

    return {
      accessToken,
      restaurantId: data.id,
      restaurantName: data.name,
      terminalName: terminalName ?? null,
    };
  }

  // ── 사장 계정(이메일+비번)으로 LSPOS 로그인 ────────────
  // LSPOS 가 restaurantId 없이 사장 계정 자격증명만으로 로그인하는 신규 경로.
  //
  // 응답:
  //   userToken   — USER JWT. 식당 미등록 시 식당 생성(POST /pos/restaurants)에 사용.
  //   restaurant  — 이미 식당이 등록된 경우. posToken 포함 → 바로 대시보드 진입 가능.
  //                 미등록이면 null → LSPOS 가 식당 등록 화면으로 안내.
  async loginOwner(
    email: string,
    password: string,
  ): Promise<{
    userToken: string;
    restaurant: {
      posToken: string;
      restaurantId: string;
      restaurantName: string;
    } | null;
  }> {
    // 1. 이메일로 사용자 조회
    const { data: user, error: userLookupError } = await this.supabase.client
      .from('users')
      .select(
        'id, name, password_hash, role, status, email_verified_at, restaurant_id',
      )
      .ilike('email', this.emailLookupPattern(email))
      .maybeSingle();

    if (userLookupError) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'POS_OWNER_LOOKUP_FAILED',
        message:
          '점주 계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }

    if (!user || !user.password_hash) {
      throw new UnauthorizedException(
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
    }

    // 2. 비밀번호 검증
    const isValid = await bcrypt.compare(password, user.password_hash);
    if (!isValid) {
      throw new UnauthorizedException(
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
    }

    if (!user.email_verified_at) {
      throw new UnauthorizedException({
        statusCode: 401,
        code: 'EMAIL_VERIFICATION_REQUIRED',
        message: '이메일 인증을 완료한 뒤 POS에 로그인해주세요.',
        retryable: false,
      });
    }

    if (user.role !== 'OWNER' || user.status !== 'APPROVED') {
      throw new UnauthorizedException(
        '승인된 사장 계정만 POS에 로그인할 수 있습니다.',
      );
    }

    // 3. USER JWT 발급 (식당 등록 API 호출에 사용)
    const userToken = this.jwt.sign({ sub: user.id, type: 'USER' });

    // 4. 등록된 식당 조회
    const { data: canonicalRestaurant, error: canonicalLookupError } =
      await this.supabase.client
        .from('restaurants')
        .select('id, name')
        .eq('owner_user_id', user.id)
        .maybeSingle();

    if (canonicalLookupError) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'POS_RESTAURANT_LOOKUP_FAILED',
        message: '매장 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }

    let restaurant = canonicalRestaurant;
    if (!restaurant && user.restaurant_id) {
      const { data: legacyRestaurant, error: legacyLookupError } =
        await this.supabase.client
          .from('restaurants')
          .select('id, name, owner_user_id')
          .eq('id', user.restaurant_id)
          .maybeSingle();
      if (legacyLookupError) {
        throw new ServiceUnavailableException({
          statusCode: 503,
          code: 'POS_RESTAURANT_LOOKUP_FAILED',
          message:
            '매장 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
          retryable: true,
        });
      }
      if (legacyRestaurant && legacyRestaurant.owner_user_id === user.id) {
        restaurant = legacyRestaurant;
      } else if (legacyRestaurant && legacyRestaurant.owner_user_id == null) {
        const { data: competingLegacyOwner, error: legacyMappingError } =
          await this.supabase.client
            .from('users')
            .select('id')
            .eq('restaurant_id', legacyRestaurant.id)
            .neq('id', user.id)
            .limit(1)
            .maybeSingle();
        if (legacyMappingError) {
          throw new ServiceUnavailableException({
            statusCode: 503,
            code: 'POS_OWNERSHIP_LOOKUP_FAILED',
            message:
              '매장 소유권을 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
            retryable: true,
          });
        }
        if (competingLegacyOwner) {
          throw new ConflictException({
            statusCode: 409,
            code: 'POS_LEGACY_OWNERSHIP_AMBIGUOUS',
            message:
              '여러 계정에 연결된 기존 매장입니다. 관리자에게 소유권 정리를 요청해주세요.',
            retryable: false,
          });
        }

        const { data: claimedRestaurant, error: claimError } =
          await this.supabase.client
            .from('restaurants')
            .update({ owner_user_id: user.id })
            .eq('id', legacyRestaurant.id)
            .is('owner_user_id', null)
            .select('id, name, owner_user_id')
            .maybeSingle();
        if (claimError) {
          throw new ServiceUnavailableException({
            statusCode: 503,
            code: 'POS_OWNERSHIP_CLAIM_FAILED',
            message:
              '매장 소유권을 동기화하지 못했습니다. 잠시 후 다시 시도해주세요.',
            retryable: true,
          });
        }
        if (!claimedRestaurant) {
          throw new ConflictException({
            statusCode: 409,
            code: 'POS_OWNERSHIP_CLAIM_CONFLICT',
            message: '매장 소유권이 변경되었습니다. 다시 로그인해주세요.',
            retryable: true,
          });
        }
        restaurant = claimedRestaurant;
      }
    }

    if (!restaurant) {
      return { userToken, restaurant: null };
    }

    // 5. 식당 있으면 POS JWT도 함께 발급
    const posToken = this.jwt.sign(
      {
        sub: restaurant.id,
        type: 'POS',
        ownerUserId: user.id,
        authMode: 'OWNER',
      },
      { expiresIn: '8h' },
    );

    return {
      userToken,
      restaurant: {
        posToken,
        restaurantId: restaurant.id,
        restaurantName: restaurant.name,
      },
    };
  }

  private emailLookupPattern(email: string): string {
    return email.trim().replace(/[\\%_]/g, '\\$&');
  }
}
