import { Injectable, NotFoundException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
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
//   restaurants 테이블에 해당 ID 가 실제 존재할 때만 발급.
//   캡스톤 단계: PIN/단말 토큰 등 추가 보안 없음.
//   운영 전환 시 PosAuthService.loginWithPin(pin) 같은 메서드 추가.
// ══════════════════════════════════════════════════════════

@Injectable()
export class PosAuthService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly jwt: JwtService,
  ) {}

  /// POS 단말 로그인 — restaurantId 검증 후 type=POS JWT 발급.
  /// 성공 시: { accessToken, restaurantId, restaurantName }
  /// 실패 시: NotFoundException
  async login(restaurantId: string, terminalName?: string) {
    // 식당 존재 여부 확인 — 잘못된 UUID 또는 미등록 식당 차단
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
    const accessToken = this.jwt.sign({
      sub: data.id,
      type: 'POS',
    });

    return {
      accessToken,
      restaurantId: data.id,
      restaurantName: data.name,
      terminalName: terminalName ?? null,
    };
  }
}
