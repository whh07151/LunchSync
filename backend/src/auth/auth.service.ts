import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { SupabaseService } from '../supabase/supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 카카오 로그인 비즈니스 로직
//
// 전체 흐름:
//   1. Flutter에서 카카오 access token을 받음
//   2. 카카오 API 호출해서 kakao_id / nickname / profile_image 조회
//   3. Supabase users 테이블에서 kakao_id로 기존 유저 조회
//   4. 없으면 신규 유저 INSERT (name = 카카오 닉네임, role = CUSTOMER)
//   5. 자체 JWT 발급 후 반환
// ══════════════════════════════════════════════════════════

// 카카오 /v2/user/me API 응답 타입 (필요한 필드만 정의)
interface KakaoUserInfo {
  id: number;
  kakao_account?: {
    profile?: {
      nickname?: string;
      profile_image_url?: string;
    };
  };
}

// 로그인/회원가입 결과 반환 타입
export interface AuthResult {
  accessToken: string; // LunchSync 자체 JWT
  isNewUser: boolean;  // true: 신규(온보딩 필요), false: 기존(홈으로 바로)
  user: {
    id: string;
    name: string;
    profileImage: string | null;
    role: string; // 유저 역할 (CUSTOMER | OWNER 등)
  };
}

@Injectable()
export class AuthService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwtService: JwtService,
  ) {}

  // ── 카카오 로그인/회원가입 처리 ──────────────────────────
  // Flutter → POST /auth/kakao { kakaoAccessToken } 처리
  async kakaoLogin(kakaoAccessToken: string): Promise<AuthResult> {
    // ── 1단계: 카카오 API로 유저 정보 조회 ────────────────
    const kakaoUser = await this.getKakaoUserInfo(kakaoAccessToken);

    const kakaoId = String(kakaoUser.id);
    const nickname = kakaoUser.kakao_account?.profile?.nickname ?? '이름 없음';
    const profileImage = kakaoUser.kakao_account?.profile?.profile_image_url ?? null;

    // ── 2단계: Supabase에서 기존 유저 조회 ──────────────────
    const { data: existingUser } = await this.supabase.client
      .from('users')
      .select('id, name, profile_image')
      .eq('kakao_id', kakaoId)
      .single();

    // ── 3단계: 신규 유저면 INSERT ─────────────────────────
    let userId: string;
    let userName: string;
    let isNewUser: boolean;

    if (existingUser) {
      // 기존 유저: 그대로 사용
      userId = existingUser.id;
      userName = existingUser.name;
      isNewUser = false;
    } else {
      // 신규 유저: 카카오 닉네임으로 기본 레코드 생성
      // 이름/소속/반경 등 상세 정보는 온보딩(CU-03, CU-05)에서 PATCH /users/me로 업데이트
      const { data: newUser, error } = await this.supabase.client
        .from('users')
        .insert({
          kakao_id: kakaoId,
          name: nickname,       // 온보딩 전 임시 이름 (카카오 닉네임)
          profile_image: profileImage,
          role: 'CUSTOMER',
          radius: '500m',       // 온보딩 전 기본값
        })
        .select('id, name')
        .single();

      if (error || !newUser) {
        throw new Error(`유저 생성 실패: ${error?.message}`);
      }

      userId = newUser.id;
      userName = newUser.name;
      isNewUser = true;
    }

    // ── 4단계: 자체 JWT 발급 ─────────────────────────────
    // JWT payload에 user_id를 넣어두면 이후 모든 API에서
    // Authorization 헤더만 있으면 누구인지 알 수 있음
    const accessToken = this.jwtService.sign({ sub: userId });

    return {
      accessToken,
      isNewUser,
      user: {
        id: userId,
        name: userName,
        profileImage,
        role: 'CUSTOMER', // 손님앱 로그인은 항상 CUSTOMER
      },
    };
  }

  // ── 카카오 API 호출: 유저 정보 조회 ─────────────────────
  // 카카오 access token으로 kakao_id / 닉네임 / 프로필사진 조회
  // 실패 시 UnauthorizedException (401) 발생
  private async getKakaoUserInfo(accessToken: string): Promise<KakaoUserInfo> {
    const response = await fetch('https://kapi.kakao.com/v2/user/me', {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });

    if (!response.ok) {
      throw new UnauthorizedException('유효하지 않은 카카오 토큰입니다.');
    }

    return response.json() as Promise<KakaoUserInfo>;
  }
}
