import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// ══════════════════════════════════════════════════════════
// 파일 역할: JWT 인증 가드
//
// 사용법:
//   @UseGuards(JwtAuthGuard) 데코레이터를 컨트롤러나
//   개별 엔드포인트에 붙이면 JWT 검증을 자동으로 수행
//
// JWT가 없거나 유효하지 않으면 401 Unauthorized 반환
// JWT가 유효하면 req.user = { userId: '...' } 주입
// ══════════════════════════════════════════════════════════

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
