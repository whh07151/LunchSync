import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PosController } from './pos.controller';
import { PosService } from './pos.service';
import { PosAuthController } from './pos-auth.controller';
import { PosAuthService } from './pos-auth.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 점주앱/POS 모듈
//
// 컨트롤러:
//   PosController     — 인증 필요 엔드포인트 (orders/stats/status/cancel)
//   PosAuthController — POS 단말 로그인 (인증 없이 호출, 신설 2026-05-12 LSPOS 통합)
//
// 서비스:
//   PosService     — 주문/통계/상태변경 로직
//   PosAuthService — POS JWT 발급 로직
//
// AuthModule 의존:
//   - JwtAuthGuard (PosController 보호)
//   - JwtModule    (PosAuthService 가 JwtService 주입받기 위해 export 됨)
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule],
  controllers: [PosController, PosAuthController],
  providers: [PosService, PosAuthService],
})
export class PosModule {}
