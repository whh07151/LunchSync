import {
  BadRequestException,
  ConflictException,
  Injectable,
  InternalServerErrorException,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';
import { FirebaseService } from './firebase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 인증 비즈니스 로직 — 카카오 + 이메일 + (추후) 휴대폰
//
// 지원 가입/로그인 경로:
//   1. 카카오 OAuth   — kakaoLogin()
//   2. 이메일+비번    — emailSignup() / emailLogin()
//   3. (추후) 휴대폰  — phoneVerify() — Firebase Phone Auth 통합 시 추가
//
// 공통 출력:
//   AuthResult { accessToken, isNewUser, nextStep, user }
//   user.role  : CUSTOMER | OWNER
//   user.status: PENDING | APPROVED | REJECTED  (OWNER 승인제용)
//
// OWNER 승인 흐름:
//   1. emailSignup() with role='OWNER' → status='PENDING' INSERT
//   2. 운영자가 Supabase 콘솔에서 status='APPROVED' 직접 변경
//   3. 다음 로그인 시 status가 응답에 포함 → Flutter가 사장 화면 진입 결정
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
  isNewUser: boolean;  // true: 신규(온보딩 필요), false: 기존(홈으로 바로) — 하위 호환용

  /// Flutter가 다음에 보여줄 화면을 서버가 결정해서 내려줌 (서버 드리븐 네비게이션)
  /// "PROFILE_SETUP"   → CU-03: 온보딩 미시작
  /// "CONDITION_SETUP" → CU-05: CU-03 완료 후 앱 종료, 조건 설정 재진입
  /// "HOME"            → 온보딩 완전 완료, 홈 대시보드로 바로 진입
  /// "OWNER_PENDING"   → OWNER 가입 후 승인 대기 중 (사장 화면 진입 차단)
  /// "OWNER_HOME"      → OWNER 승인 완료, 사장 화면으로 바로 진입
  nextStep: 'PROFILE_SETUP' | 'CONDITION_SETUP' | 'HOME' | 'OWNER_PENDING' | 'OWNER_HOME';

  user: {
    id: string;
    name: string;
    profileImage: string | null;
    role: 'CUSTOMER' | 'OWNER';
    status: 'PENDING' | 'APPROVED' | 'REJECTED';
  };
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  // bcrypt salt rounds — 10이 일반 권장값 (해시 한 번에 약 100ms)
  private readonly BCRYPT_SALT_ROUNDS = 10;

  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwtService: JwtService,
    private readonly firebase: FirebaseService,
  ) {}

  // ════════════════════════════════════════════════════════
  // 1) 카카오 로그인/회원가입
  // ════════════════════════════════════════════════════════

  // ── 카카오 로그인/회원가입 처리 ──────────────────────────
  // Flutter → POST /auth/kakao { kakaoAccessToken } 처리
  async kakaoLogin(kakaoAccessToken: string): Promise<AuthResult> {
    // ── 1단계: 카카오 API로 유저 정보 조회 ────────────────
    const kakaoUser = await this.getKakaoUserInfo(kakaoAccessToken);

    const kakaoId = String(kakaoUser.id);
    const nickname = kakaoUser.kakao_account?.profile?.nickname ?? '이름 없음';
    const profileImage = kakaoUser.kakao_account?.profile?.profile_image_url ?? null;

    // ── 2단계: Supabase에서 기존 유저 조회 ──────────────────
    // role/status: 사장 승인 흐름 분기에 필요
    const { data: existingUser } = await this.supabase.client
      .from('users')
      .select('id, name, profile_image, org, budget, speed, role, status')
      .eq('kakao_id', kakaoId)
      .single();

    let userId: string;
    let userName: string;
    let userRole: 'CUSTOMER' | 'OWNER';
    let userStatus: 'PENDING' | 'APPROVED' | 'REJECTED';
    let isNewUser: boolean;
    let nextStep: AuthResult['nextStep'];

    if (existingUser) {
      // ── 기존 유저: role/status 기반으로 nextStep 결정 ──
      userId = existingUser.id;
      userName = existingUser.name;
      userRole = (existingUser.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
      userStatus = (existingUser.status as 'PENDING' | 'APPROVED' | 'REJECTED') ?? 'APPROVED';
      isNewUser = false;

      nextStep = this.resolveNextStepForExistingUser(
        userRole,
        userStatus,
        existingUser.org,
        existingUser.budget,
        existingUser.speed,
      );
    } else {
      // ── 신규 카카오 가입자: CUSTOMER로 INSERT ──
      // 카카오로 신규 가입할 때는 항상 CUSTOMER. OWNER 가입은 이메일 가입에서만.
      const { data: newUser, error } = await this.supabase.client
        .from('users')
        .insert({
          kakao_id: kakaoId,
          name: nickname,
          profile_image: profileImage,
          role: 'CUSTOMER',
          status: 'APPROVED',     // 카카오는 본인확인 완료 → 즉시 활성화
          auth_provider: 'KAKAO',
          radius: '500m',
        })
        .select('id, name')
        .single();

      if (error || !newUser) {
        // 500: DB INSERT 실패 — Supabase 장애/제약 위반 등
        throw new InternalServerErrorException(
          `유저 생성 실패: ${error?.message}`,
        );
      }

      userId = newUser.id;
      userName = newUser.name;
      userRole = 'CUSTOMER';
      userStatus = 'APPROVED';
      isNewUser = true;
      nextStep = 'PROFILE_SETUP'; // 신규 손님은 항상 CU-03부터
    }

    // ── 3단계: 자체 JWT 발급 ─────────────────────────────
    const accessToken = this.jwtService.sign({ sub: userId });

    return {
      accessToken,
      isNewUser,
      nextStep,
      user: {
        id: userId,
        name: userName,
        profileImage,
        role: userRole,
        status: userStatus,
      },
    };
  }

  // ════════════════════════════════════════════════════════
  // 2) 이메일 회원가입
  // ════════════════════════════════════════════════════════

  // ── 이메일+비밀번호로 회원가입 ────────────────────────
  // role: CUSTOMER 또는 OWNER 선택. OWNER는 status=PENDING으로 저장됨.
  //
  // 흐름:
  //   1. 이메일 중복 체크
  //   2. 비밀번호 bcrypt 해시
  //   3. INSERT (role/status 분기)
  //   4. JWT 발급
  //
  // [캡스톤 단순화] 이메일 OTP 본인확인은 추후 추가. 지금은 즉시 가입 완료.
  async emailSignup(params: {
    email: string;
    password: string;
    name: string;
    role: 'CUSTOMER' | 'OWNER';
    businessName?: string;     // role=OWNER일 때만
    businessNumber?: string;   // role=OWNER일 때만
  }): Promise<AuthResult> {
    const { email, password, name, role, businessName, businessNumber } = params;

    // ── OWNER 가입 시 가게 정보 필수 검증 ──
    if (role === 'OWNER' && (!businessName || !businessNumber)) {
      throw new BadRequestException('OWNER 가입 시 상호명과 사업자등록번호가 필요합니다.');
    }

    // ── 1단계: 이메일 중복 체크 ───────────────────────────
    const { data: existing } = await this.supabase.client
      .from('users')
      .select('id')
      .eq('email', email)
      .maybeSingle();

    if (existing) {
      throw new ConflictException('이미 가입된 이메일입니다.');
    }

    // ── 2단계: 비밀번호 해시 ─────────────────────────────
    const passwordHash = await bcrypt.hash(password, this.BCRYPT_SALT_ROUNDS);

    // ── 3단계: 유저 INSERT ───────────────────────────────
    // CUSTOMER → status=APPROVED (즉시 활성화)
    // OWNER    → status=PENDING (운영자 승인 대기)
    const status: 'APPROVED' | 'PENDING' = role === 'OWNER' ? 'PENDING' : 'APPROVED';

    // kakao_id 컬럼이 NOT NULL 이지만 이메일 가입은 카카오 ID 가 없음.
    // 충돌 방지를 위해 `EMAIL_${타임스탬프}_${이메일}` 형식의 가상 ID 부여
    // (2026-05-12 박검토 후 추가 — 추후 컬럼 NULLABLE 마이그레이션으로 대체 예정).
    const dummyKakaoId = `EMAIL_${Date.now()}_${email}`;

    const { data: newUser, error } = await this.supabase.client
      .from('users')
      .insert({
        kakao_id: dummyKakaoId,
        email,
        password_hash: passwordHash,
        name,
        role,
        status,
        auth_provider: 'EMAIL',
        radius: '500m',
        business_name: businessName ?? null,
        business_number: businessNumber ?? null,
      })
      .select('id, name, role, status')
      .single();

    if (error || !newUser) {
      // 500: 회원가입 INSERT 실패 — 백엔드 로그로 원인 추적
      throw new InternalServerErrorException(
        `회원가입 실패: ${error?.message}`,
      );
    }

    // ── 4단계: JWT 발급 ──────────────────────────────────
    const accessToken = this.jwtService.sign({ sub: newUser.id });

    // ── nextStep 결정 ────────────────────────────────────
    // OWNER 가입 직후 → 항상 OWNER_PENDING (승인 대기 안내 화면)
    // CUSTOMER 가입 직후 → PROFILE_SETUP (이름은 입력했지만 소속/조건 미입력)
    const nextStep: AuthResult['nextStep'] =
      role === 'OWNER' ? 'OWNER_PENDING' : 'PROFILE_SETUP';

    return {
      accessToken,
      isNewUser: true,
      nextStep,
      user: {
        id: newUser.id,
        name: newUser.name,
        profileImage: null,
        role: newUser.role as 'CUSTOMER' | 'OWNER',
        status: newUser.status as 'PENDING' | 'APPROVED' | 'REJECTED',
      },
    };
  }

  // ════════════════════════════════════════════════════════
  // 3) 이메일 로그인
  // ════════════════════════════════════════════════════════

  // ── 이메일+비밀번호 로그인 ──────────────────────────────
  // 비밀번호 불일치 / 미존재 모두 같은 메시지로 응답 (계정 존재 여부 노출 방지)
  async emailLogin(email: string, password: string): Promise<AuthResult> {
    const { data: user } = await this.supabase.client
      .from('users')
      .select(
        'id, name, profile_image, password_hash, role, status, org, budget, speed',
      )
      .eq('email', email)
      .maybeSingle();

    if (!user || !user.password_hash) {
      throw new UnauthorizedException('이메일 또는 비밀번호가 올바르지 않습니다.');
    }

    // ── 비밀번호 검증 ──
    const isValid = await bcrypt.compare(password, user.password_hash);
    if (!isValid) {
      throw new UnauthorizedException('이메일 또는 비밀번호가 올바르지 않습니다.');
    }

    const userRole = (user.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
    const userStatus = (user.status as 'PENDING' | 'APPROVED' | 'REJECTED') ?? 'APPROVED';

    const nextStep = this.resolveNextStepForExistingUser(
      userRole,
      userStatus,
      user.org,
      user.budget,
      user.speed,
    );

    const accessToken = this.jwtService.sign({ sub: user.id });

    return {
      accessToken,
      isNewUser: false,
      nextStep,
      user: {
        id: user.id,
        name: user.name,
        profileImage: user.profile_image,
        role: userRole,
        status: userStatus,
      },
    };
  }

  // ════════════════════════════════════════════════════════
  // 4) 휴대폰 인증 (Firebase Phone Auth)
  // ════════════════════════════════════════════════════════

  // ── Firebase ID 토큰 검증 + 사용자 갱신/생성 ────────────
  // Flutter → POST /auth/verify-phone { idToken, existingUserId? } 처리.
  //
  // 두 가지 모드를 지원한다:
  //   (A) existingUserId 전달  : 로그인 중인 사용자에게 휴대폰 본인확인을 붙임
  //                             - users.phone_number / phone_verified_at 갱신
  //                             - nextStep 은 기존 사용자 로직 그대로 계산
  //   (B) existingUserId 미전달: 전화번호 기반으로 사용자 조회.
  //                             - 일치 사용자 있음 → 로그인 처리
  //                             - 없음 → CUSTOMER 신규 가입 (auth_provider='PHONE')
  //
  // 카카오 로그인과 동일하게 AuthResult 를 반환해 Flutter 측 라우팅을 통일.
  async phoneVerify(params: {
    idToken: string;
    existingUserId?: string;
  }): Promise<AuthResult> {
    const { idToken, existingUserId } = params;

    // ── 1단계: Firebase ID 토큰 검증 ──
    // verifyIdToken 내부에서 401 처리됨. 여기까지 오면 토큰은 유효.
    const { uid, phoneNumber } = await this.firebase.verifyIdToken(idToken);

    if (!phoneNumber) {
      // 토큰은 유효하지만 phone_number 클레임이 비어 있음 — Phone Auth 가 아닌 토큰.
      throw new BadRequestException(
        '휴대폰 번호가 포함되지 않은 토큰입니다. Phone Auth 로 로그인해주세요.',
      );
    }

    // ── 2단계: 분기 처리 ──
    if (existingUserId) {
      return this.attachPhoneToExistingUser(existingUserId, phoneNumber);
    }
    return this.loginOrSignupByPhone(uid, phoneNumber);
  }

  // ── (A) 로그인 중인 사용자에 휴대폰 붙이기 ──────────────
  // 다른 사람의 휴대폰을 중복으로 붙이는 걸 막기 위해, 같은 번호가
  // 다른 user_id 에 이미 등록돼 있으면 ConflictException 으로 거부.
  private async attachPhoneToExistingUser(
    userId: string,
    phoneNumber: string,
  ): Promise<AuthResult> {
    // 다른 사용자가 같은 번호를 이미 쓰고 있는지 확인
    const { data: collide } = await this.supabase.client
      .from('users')
      .select('id')
      .eq('phone_number', phoneNumber)
      .neq('id', userId)
      .maybeSingle();

    if (collide) {
      throw new ConflictException('이미 다른 계정에 등록된 번호입니다.');
    }

    const verifiedAt = new Date().toISOString();
    const { data: updated, error } = await this.supabase.client
      .from('users')
      .update({
        phone_number: phoneNumber,
        phone_verified_at: verifiedAt,
      })
      .eq('id', userId)
      .select(
        'id, name, profile_image, role, status, org, budget, speed',
      )
      .single();

    if (error || !updated) {
      this.logger.error(`휴대폰 갱신 실패 (user=${userId}): ${error?.message}`);
      throw new BadRequestException('사용자를 찾을 수 없습니다.');
    }

    const userRole = (updated.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
    const userStatus =
      (updated.status as 'PENDING' | 'APPROVED' | 'REJECTED') ?? 'APPROVED';

    const nextStep = this.resolveNextStepForExistingUser(
      userRole,
      userStatus,
      updated.org,
      updated.budget,
      updated.speed,
    );

    // 기존 사용자이므로 새 JWT 를 굳이 갱신하지 않아도 되지만,
    // 응답 구조 통일을 위해 갱신 토큰 발급 (Flutter 가 같은 로직으로 처리하도록)
    const accessToken = this.jwtService.sign({ sub: updated.id });

    return {
      accessToken,
      isNewUser: false,
      nextStep,
      user: {
        id: updated.id,
        name: updated.name,
        profileImage: updated.profile_image,
        role: userRole,
        status: userStatus,
      },
    };
  }

  // ── (B) 전화번호로 로그인/회원가입 ──────────────────────
  // 기존 사용자(phone_number 일치) 있으면 로그인 처리.
  // 없으면 CUSTOMER 신규 가입 (auth_provider='PHONE', status='APPROVED').
  //
  // 참고: firebaseUid 는 현재 컬럼이 없어 저장하지 않는다. 향후 컬럼 추가 시
  // 여기서 함께 INSERT 하면 됨.
  private async loginOrSignupByPhone(
    _firebaseUid: string,
    phoneNumber: string,
  ): Promise<AuthResult> {
    const verifiedAt = new Date().toISOString();

    // 기존 사용자 조회
    const { data: existingUser } = await this.supabase.client
      .from('users')
      .select(
        'id, name, profile_image, role, status, org, budget, speed',
      )
      .eq('phone_number', phoneNumber)
      .maybeSingle();

    let userId: string;
    let userName: string;
    let profileImage: string | null;
    let userRole: 'CUSTOMER' | 'OWNER';
    let userStatus: 'PENDING' | 'APPROVED' | 'REJECTED';
    let isNewUser: boolean;
    let nextStep: AuthResult['nextStep'];

    if (existingUser) {
      // ── 기존 사용자: 로그인 흐름 ──
      userId = existingUser.id;
      userName = existingUser.name;
      profileImage = existingUser.profile_image;
      userRole = (existingUser.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
      userStatus =
        (existingUser.status as 'PENDING' | 'APPROVED' | 'REJECTED') ??
        'APPROVED';
      isNewUser = false;

      // 인증 시각만 최신화 (실패해도 로그인은 진행)
      await this.supabase.client
        .from('users')
        .update({ phone_verified_at: verifiedAt })
        .eq('id', userId);

      nextStep = this.resolveNextStepForExistingUser(
        userRole,
        userStatus,
        existingUser.org,
        existingUser.budget,
        existingUser.speed,
      );
    } else {
      // ── 신규 휴대폰 가입자: CUSTOMER 로 INSERT ──
      const { data: newUser, error } = await this.supabase.client
        .from('users')
        .insert({
          name: '이름 없음', // 온보딩에서 사용자가 채울 예정
          phone_number: phoneNumber,
          phone_verified_at: verifiedAt,
          role: 'CUSTOMER',
          status: 'APPROVED',
          auth_provider: 'PHONE',
          radius: '500m',
        })
        .select('id, name, profile_image')
        .single();

      if (error || !newUser) {
        this.logger.error(`휴대폰 가입 실패 (${phoneNumber}): ${error?.message}`);
        throw new BadRequestException('휴대폰 회원가입에 실패했어요.');
      }

      userId = newUser.id;
      userName = newUser.name;
      profileImage = newUser.profile_image;
      userRole = 'CUSTOMER';
      userStatus = 'APPROVED';
      isNewUser = true;
      nextStep = 'PROFILE_SETUP'; // 신규 가입은 온보딩부터
    }

    const accessToken = this.jwtService.sign({ sub: userId });

    return {
      accessToken,
      isNewUser,
      nextStep,
      user: {
        id: userId,
        name: userName,
        profileImage,
        role: userRole,
        status: userStatus,
      },
    };
  }

  // ════════════════════════════════════════════════════════
  // 공통 헬퍼
  // ════════════════════════════════════════════════════════

  // ── 기존 유저 로그인 시 nextStep 결정 로직 ──────────────
  // role/status/온보딩 진행상태를 종합해 다음 화면을 결정.
  private resolveNextStepForExistingUser(
    role: 'CUSTOMER' | 'OWNER',
    status: 'PENDING' | 'APPROVED' | 'REJECTED',
    org: string | null | undefined,
    budget: number | null | undefined,
    speed: string | null | undefined,
  ): AuthResult['nextStep'] {
    // ── OWNER 분기 ──
    // 승인 대기/거부 상태면 무조건 안내 화면. 승인 완료면 사장 홈으로.
    if (role === 'OWNER') {
      if (status !== 'APPROVED') return 'OWNER_PENDING';
      return 'OWNER_HOME';
    }

    // ── CUSTOMER 분기: 기존 온보딩 진행 상태 로직 그대로 ──
    if (!org) return 'PROFILE_SETUP';
    if (budget == null || !speed) return 'CONDITION_SETUP';
    return 'HOME';
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
