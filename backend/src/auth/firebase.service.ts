// ══════════════════════════════════════════════════════════
// 파일 역할: Firebase Admin SDK 래퍼 서비스
//
// 책임:
//   1) 앱 부팅 시 Firebase Admin SDK 초기화 (서비스 계정 JSON 로드)
//   2) Flutter 가 전달한 Phone Auth ID 토큰을 검증해 phone_number / uid 추출
//
// 의존:
//   - .env: FIREBASE_PROJECT_ID, FIREBASE_ADMIN_KEY_PATH
//   - 서비스 계정 키 JSON: backend/secrets/firebase-admin-key.json (gitignore됨)
//
// 흐름:
//   Flutter → signInWithPhoneNumber() → OTP 검증 → ID 토큰 발급
//   → POST /api/auth/verify-phone { idToken } → FirebaseService.verifyIdToken()
//   → DecodedIdToken.phone_number / uid 반환
//   → AuthService 가 users 테이블 업데이트
// ══════════════════════════════════════════════════════════

import {
  Injectable,
  Logger,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as path from 'path';

@Injectable()
export class FirebaseService implements OnModuleInit {
  private readonly logger = new Logger(FirebaseService.name);

  // Firebase Admin App 인스턴스 — 모듈당 1개만 초기화 (싱글톤)
  private app: admin.app.App | null = null;

  constructor(private readonly config: ConfigService) {}

  // ── NestJS 라이프사이클: 모듈 로드 시 Firebase 초기화 ──
  // OnModuleInit 으로 한 번만 실행. 이미 초기화돼 있으면 기존 app 재사용.
  onModuleInit(): void {
    if (admin.apps.length > 0) {
      this.app = admin.app();
      this.logger.log('Firebase Admin SDK already initialized — 기존 app 재사용');
      return;
    }

    const projectId = this.config.get<string>('FIREBASE_PROJECT_ID');
    const keyPath = this.config.get<string>('FIREBASE_ADMIN_KEY_PATH');

    if (!projectId || !keyPath) {
      // .env 미설정 시 — 개발 환경에서 카카오/이메일만 쓸 때는 정상 케이스.
      // 휴대폰 인증 호출 시점에 명확한 에러를 던지므로 여기서는 경고만.
      this.logger.warn(
        'FIREBASE_PROJECT_ID 또는 FIREBASE_ADMIN_KEY_PATH 미설정 — Firebase Phone Auth 비활성',
      );
      return;
    }

    // 상대 경로는 backend/ 폴더 기준으로 해석 (process.cwd() = backend 디렉터리)
    const absoluteKeyPath = path.isAbsolute(keyPath)
      ? keyPath
      : path.resolve(process.cwd(), keyPath);

    if (!fs.existsSync(absoluteKeyPath)) {
      this.logger.error(
        `Firebase 서비스 계정 키 파일을 찾을 수 없음: ${absoluteKeyPath}`,
      );
      return;
    }

    // JSON 파일을 동기 로드 (앱 부팅 1회만 실행되므로 동기 안전)
    const serviceAccount = JSON.parse(
      fs.readFileSync(absoluteKeyPath, 'utf-8'),
    ) as admin.ServiceAccount;

    this.app = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
    });

    this.logger.log(
      `Firebase Admin SDK 초기화 완료 — projectId=${projectId}`,
    );
  }

  // ── ID 토큰 검증 ───────────────────────────────────────
  // Flutter → POST /auth/verify-phone { idToken } 로 받은 토큰을 검증.
  //
  // 반환값:
  //   - uid          : Firebase 가 발급한 사용자 식별자 (예: 'kK3...')
  //   - phoneNumber  : E.164 형식 (예: '+821012345678'). 검증 안 됐으면 null.
  //
  // 실패 조건:
  //   - Firebase 미초기화 → 500 (사실상 .env 누락)
  //   - 토큰 위조/만료    → 401
  async verifyIdToken(idToken: string): Promise<{
    uid: string;
    phoneNumber: string | null;
  }> {
    if (!this.app) {
      this.logger.error('Firebase 미초기화 상태에서 verifyIdToken 호출됨');
      throw new UnauthorizedException(
        '휴대폰 인증 서비스가 활성화돼 있지 않습니다.',
      );
    }

    try {
      const decoded = await admin.auth(this.app).verifyIdToken(idToken);
      return {
        uid: decoded.uid,
        // phone_number 는 Phone Auth 로 로그인한 경우에만 채워짐
        phoneNumber: (decoded.phone_number as string | undefined) ?? null,
      };
    } catch (err) {
      this.logger.warn(
        `Firebase ID 토큰 검증 실패: ${(err as Error).message}`,
      );
      throw new UnauthorizedException('유효하지 않은 Firebase 토큰입니다.');
    }
  }
}
