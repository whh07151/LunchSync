import {
  BadRequestException,
  ConflictException,
  Injectable,
  InternalServerErrorException,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
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
  accessToken: string; // LunchSync JWT. 이메일 가입 직후에는 검증 전용 제한 토큰.
  isNewUser: boolean; // true: 신규(온보딩 필요), false: 기존(홈으로 바로) — 하위 호환용

  /// Flutter가 다음에 보여줄 화면을 서버가 결정해서 내려줌 (서버 드리븐 네비게이션)
  /// "PROFILE_SETUP"   → CU-03: 온보딩 미시작
  /// "CONDITION_SETUP" → CU-05: CU-03 완료 후 앱 종료, 조건 설정 재진입
  /// "HOME"            → 온보딩 완전 완료, 홈 대시보드로 바로 진입
  /// "OWNER_PENDING"   → OWNER 가입 후 승인 대기 중 (사장 화면 진입 차단)
  /// "OWNER_HOME"      → OWNER 승인 완료, 사장 화면으로 바로 진입
  nextStep:
    | 'PROFILE_SETUP'
    | 'CONDITION_SETUP'
    | 'HOME'
    | 'OWNER_PENDING'
    | 'OWNER_HOME';

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
    private readonly config: ConfigService = new ConfigService(),
  ) {}

  // ════════════════════════════════════════════════════════
  // 1) 카카오 로그인/회원가입
  // ════════════════════════════════════════════════════════

  // ── 카카오 로그인/회원가입 처리 ──────────────────────────
  // Flutter → POST /auth/kakao { kakaoAccessToken } 처리
  async kakaoLogin(kakaoAccessToken: string): Promise<AuthResult> {
    const kakaoUser = await this.getKakaoUserInfo(kakaoAccessToken);
    const kakaoId = String(kakaoUser.id);
    const nickname = kakaoUser.kakao_account?.profile?.nickname ?? '이름 없음';
    const profileImage =
      kakaoUser.kakao_account?.profile?.profile_image_url ?? null;

    let user = await this.lookupKakaoAccount(kakaoId);
    let isNewUser = false;
    if (!user) {
      const { data: created, error } = await this.supabase.client
        .from('users')
        .insert({
          kakao_id: kakaoId,
          name: nickname,
          profile_image: profileImage,
          role: 'CUSTOMER',
          status: 'APPROVED',
          auth_provider: 'KAKAO',
          radius: '500m',
        })
        .select('id, name, profile_image, org, budget, speed, role, status')
        .single();

      if (error?.code === '23505') {
        // A concurrent first login may have created this identity. Never
        // overwrite its profile, role or onboarding state with an upsert.
        user = await this.lookupKakaoAccount(kakaoId);
      } else if (!error && created) {
        user = created;
        isNewUser = true;
      }

      if (!user) {
        this.logger.error('KAKAO_SIGNUP_PERSIST_FAILED');
        throw this.kakaoUnavailable('KAKAO_SIGNUP_PERSIST_FAILED');
      }
    }

    const role = (user.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
    const status =
      (user.status as 'PENDING' | 'APPROVED' | 'REJECTED') ?? 'APPROVED';
    const nextStep = this.resolveNextStepForExistingUser(
      role,
      status,
      user.org,
      user.budget,
      user.speed,
    );
    return {
      accessToken: this.jwtService.sign({ sub: user.id }),
      isNewUser,
      nextStep,
      user: {
        id: user.id,
        name: user.name,
        profileImage: user.profile_image ?? null,
        role,
        status,
      },
    };
  }

  private async lookupKakaoAccount(kakaoId: string) {
    const { data, error } = await this.supabase.client
      .from('users')
      .select('id, name, profile_image, org, budget, speed, role, status')
      .eq('kakao_id', kakaoId)
      .maybeSingle();
    if (error) {
      this.logger.error('KAKAO_ACCOUNT_LOOKUP_FAILED');
      throw this.kakaoUnavailable('KAKAO_ACCOUNT_LOOKUP_FAILED');
    }
    return data;
  }

  private kakaoUnavailable(code: string): ServiceUnavailableException {
    return new ServiceUnavailableException({
      statusCode: 503,
      code,
      message:
        '카카오 로그인 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
      retryable: true,
    });
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
    businessName?: string; // role=OWNER일 때만
    businessNumber?: string; // role=OWNER일 때만
  }): Promise<AuthResult> {
    const { email, password, name, role, businessName, businessNumber } =
      params;
    const normalizedEmail = email.trim().toLowerCase();

    // ── OWNER 가입 시 가게 정보 필수 검증 ──
    if (role === 'OWNER' && (!businessName || !businessNumber)) {
      throw new BadRequestException(
        'OWNER 가입 시 상호명과 사업자등록번호가 필요합니다.',
      );
    }

    // ── 1단계: 이메일 중복 체크 ───────────────────────────
    const { data: existing, error: existingLookupError } =
      await this.supabase.client
        .from('users')
        .select('id')
        .ilike('email', this.emailLookupPattern(normalizedEmail))
        .maybeSingle();

    if (existingLookupError) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'EMAIL_ACCOUNT_LOOKUP_FAILED',
        message:
          '이메일 계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }

    if (existing) {
      throw new ConflictException('이미 가입된 이메일입니다.');
    }

    // ── 2단계: 비밀번호 해시 ─────────────────────────────
    const passwordHash = await bcrypt.hash(password, this.BCRYPT_SALT_ROUNDS);

    // ── 3단계: 유저 INSERT ───────────────────────────────
    // CUSTOMER → status=APPROVED (즉시 활성화)
    // OWNER    → status=PENDING (운영자 승인 대기)
    const status: 'APPROVED' | 'PENDING' =
      role === 'OWNER' ? 'PENDING' : 'APPROVED';

    // kakao_id 컬럼이 NOT NULL 이지만 이메일 가입은 카카오 ID 가 없음.
    // 충돌 방지를 위해 `EMAIL_${타임스탬프}_${이메일}` 형식의 가상 ID 부여
    // (2026-05-12 박검토 후 추가 — 추후 컬럼 NULLABLE 마이그레이션으로 대체 예정).
    const dummyKakaoId = `EMAIL_${Date.now()}_${normalizedEmail}`;

    const { data: newUser, error } = await this.supabase.client
      .from('users')
      .insert({
        kakao_id: dummyKakaoId,
        email: normalizedEmail,
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
      if (error?.code === '23505') {
        throw new ConflictException('이미 가입된 이메일입니다.');
      }
      this.logger.error('EMAIL_SIGNUP_PERSIST_FAILED');
      throw new InternalServerErrorException(
        '회원가입에 실패했습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    // ── 4단계: 이메일 검증 전용 제한 토큰 발급 ─────────────
    // 응답 구조 하위 호환을 유지하되 JwtStrategy가 이 purpose를 일반 API에서
    // 거절한다. 정상 API 토큰은 OTP 검증 완료 후에만 발급한다.
    const accessToken = this.issueEmailVerificationToken(
      newUser.id,
      normalizedEmail,
    );

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
    const normalizedEmail = email.trim().toLowerCase();
    const { data: user, error: lookupError } = await this.supabase.client
      .from('users')
      .select(
        'id, name, profile_image, password_hash, role, status, org, budget, speed, email_verified_at',
      )
      .ilike('email', this.emailLookupPattern(normalizedEmail))
      .maybeSingle();

    if (lookupError) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'EMAIL_ACCOUNT_LOOKUP_FAILED',
        message:
          '이메일 계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }

    if (!user || !user.password_hash) {
      throw new UnauthorizedException(
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
    }

    // ── 비밀번호 검증 ──
    const isValid = await bcrypt.compare(password, user.password_hash);
    if (!isValid) {
      throw new UnauthorizedException(
        '이메일 또는 비밀번호가 올바르지 않습니다.',
      );
    }

    if (!user.email_verified_at) {
      const verificationToken = this.issueEmailVerificationToken(
        user.id,
        normalizedEmail,
      );
      throw new UnauthorizedException({
        statusCode: 401,
        code: 'EMAIL_VERIFICATION_REQUIRED',
        message: '이메일 인증을 완료한 뒤 로그인해주세요.',
        retryable: false,
        verificationToken,
      });
    }

    const userRole = (user.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
    const userStatus =
      (user.status as 'PENDING' | 'APPROVED' | 'REJECTED') ?? 'APPROVED';

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

  // OTP 검증과 public.users 반영이 끝난 뒤에만 정상 LunchSync JWT를 발급한다.
  // 제한 토큰에 묶인 사용자/이메일로 다시 조회하고 verified 상태를 확인한다.
  async completeEmailVerification(
    userId: string,
    email: string,
  ): Promise<AuthResult> {
    const normalizedEmail = email.trim().toLowerCase();
    const { data: user, error } = await this.supabase.client
      .from('users')
      .select(
        'id, name, profile_image, role, status, org, budget, speed, email_verified_at',
      )
      .eq('id', userId)
      .ilike('email', this.emailLookupPattern(normalizedEmail))
      .maybeSingle();

    if (error) {
      this.logger.error('이메일 인증 완료 사용자 조회 실패');
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'EMAIL_VERIFICATION_SYNC_PENDING',
        message:
          '이메일 인증은 완료됐지만 로그인 정보를 불러오지 못했습니다. 잠시 후 로그인해주세요.',
        retryable: true,
      });
    }

    if (!user?.email_verified_at) {
      throw new UnauthorizedException({
        statusCode: 401,
        code: 'EMAIL_VERIFICATION_REQUIRED',
        message: '이메일 인증을 완료한 뒤 로그인해주세요.',
        retryable: false,
      });
    }

    const userRole = (user.role as 'CUSTOMER' | 'OWNER') ?? 'CUSTOMER';
    const userStatus =
      (user.status as 'PENDING' | 'APPROVED' | 'REJECTED') ?? 'APPROVED';
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
      isNewUser: true,
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
  // Flutter → POST /auth/verify-phone { idToken } 처리.
  // 공개 경로에서는 검증된 전화번호로만 로그인/가입 대상을 결정한다.
  async phoneVerify(idToken: string): Promise<AuthResult> {
    // verifyIdToken 내부에서 401 처리됨. 여기까지 오면 토큰은 유효.
    const { uid, phoneNumber } = await this.firebase.verifyIdToken(idToken);

    if (!phoneNumber) {
      // 토큰은 유효하지만 phone_number 클레임이 비어 있음 — Phone Auth 가 아닌 토큰.
      throw new BadRequestException(
        '휴대폰 번호가 포함되지 않은 토큰입니다. Phone Auth 로 로그인해주세요.',
      );
    }

    return this.loginOrSignupByPhone(uid, phoneNumber);
  }

  // 기존 계정 연결은 JwtAuthGuard로 인증된 별도 엔드포인트에서만 호출된다.
  // userId는 요청 본문이 아닌 LunchSync JWT의 sub에서 파생한다.
  async attachVerifiedPhone(
    idToken: string,
    authenticatedUserId: string | undefined,
  ): Promise<AuthResult> {
    if (!authenticatedUserId) {
      throw new UnauthorizedException('사용자 인증 정보가 없습니다.');
    }

    const { phoneNumber } = await this.firebase.verifyIdToken(idToken);
    if (!phoneNumber) {
      throw new BadRequestException(
        '휴대폰 번호가 포함되지 않은 토큰입니다. Phone Auth 로 로그인해주세요.',
      );
    }

    return this.attachPhoneToExistingUser(authenticatedUserId, phoneNumber);
  }

  // ── (A) 로그인 중인 사용자에 휴대폰 붙이기 ──────────────
  // 다른 사람의 휴대폰을 중복으로 붙이는 걸 막기 위해, 같은 번호가
  // 다른 user_id 에 이미 등록돼 있으면 ConflictException 으로 거부.
  private async attachPhoneToExistingUser(
    userId: string,
    phoneNumber: string,
  ): Promise<AuthResult> {
    // 다른 사용자가 같은 번호를 이미 쓰고 있는지 확인
    const { data: collide, error: phoneLookupError } =
      await this.supabase.client
        .from('users')
        .select('id')
        .eq('phone_number', phoneNumber)
        .neq('id', userId)
        .maybeSingle();

    if (phoneLookupError) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'PHONE_ACCOUNT_LOOKUP_FAILED',
        message:
          '휴대폰 계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }

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
      .select('id, name, profile_image, role, status, org, budget, speed')
      .single();

    if (error || !updated) {
      this.logger.error('PHONE_ATTACHMENT_PERSIST_FAILED');
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
    const { data: existingUser, error: phoneLookupError } =
      await this.supabase.client
        .from('users')
        .select('id, name, profile_image, role, status, org, budget, speed')
        .eq('phone_number', phoneNumber)
        .maybeSingle();

    if (phoneLookupError) {
      throw new ServiceUnavailableException({
        statusCode: 503,
        code: 'PHONE_ACCOUNT_LOOKUP_FAILED',
        message:
          '휴대폰 계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.',
        retryable: true,
      });
    }

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
        this.logger.error('PHONE_SIGNUP_PERSIST_FAILED');
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

  private issueEmailVerificationToken(userId: string, email: string): string {
    return this.jwtService.sign(
      {
        sub: userId,
        email: email.trim().toLowerCase(),
        purpose: 'EMAIL_VERIFICATION',
      },
      { expiresIn: '10m' },
    );
  }

  private emailLookupPattern(email: string): string {
    // ilike를 case-insensitive equality처럼 사용하되 LIKE wildcard는 escape한다.
    return email.trim().replace(/[\\%_]/g, '\\$&');
  }

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
    const appId = Number(this.config.get<string>('KAKAO_APP_ID'));
    if (!Number.isSafeInteger(appId) || appId <= 0) {
      throw this.kakaoUnavailable('KAKAO_CONFIGURATION_INVALID');
    }
    const configuredTimeout = Number(
      this.config.get<string>('KAKAO_API_TIMEOUT_MS') ?? 5000,
    );
    const timeoutMs = Number.isFinite(configuredTimeout)
      ? Math.max(1000, Math.min(configuredTimeout, 8000))
      : 5000;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const tokenInfo = await this.requestKakaoJson(
        'https://kapi.kakao.com/v1/user/access_token_info',
        accessToken,
        controller.signal,
      );
      if (
        tokenInfo.app_id !== appId ||
        !Number.isSafeInteger(tokenInfo.id) ||
        tokenInfo.id <= 0 ||
        typeof tokenInfo.expires_in !== 'number' ||
        tokenInfo.expires_in <= 0
      ) {
        throw new UnauthorizedException(
          '현재 앱에서 발급한 유효한 카카오 토큰이 아닙니다.',
        );
      }
      const user = await this.requestKakaoJson(
        'https://kapi.kakao.com/v2/user/me',
        accessToken,
        controller.signal,
      );
      if (user.id !== tokenInfo.id) {
        throw new UnauthorizedException(
          '카카오 사용자 인증 정보가 일치하지 않습니다.',
        );
      }
      return user as KakaoUserInfo;
    } finally {
      clearTimeout(timer);
    }
  }

  private async requestKakaoJson(
    url: string,
    accessToken: string,
    signal: AbortSignal,
  ): Promise<any> {
    let response: Response;
    try {
      response = await fetch(url, {
        headers: { Authorization: `Bearer ${accessToken}` },
        signal,
      });
    } catch {
      throw this.kakaoUnavailable('KAKAO_PROVIDER_UNAVAILABLE');
    }
    if (response.status === 401 || response.status === 403) {
      throw new UnauthorizedException('유효하지 않은 카카오 토큰입니다.');
    }
    if (!response.ok) {
      throw this.kakaoUnavailable('KAKAO_PROVIDER_UNAVAILABLE');
    }
    try {
      const body: unknown = await response.json();
      if (!body || typeof body !== 'object' || Array.isArray(body)) {
        throw new Error('Invalid provider response');
      }
      return body;
    } catch {
      throw this.kakaoUnavailable('KAKAO_PROVIDER_RESPONSE_INVALID');
    }
  }
}
