import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

// ══════════════════════════════════════════════════════════
// 파일 역할: Supabase 클라이언트 싱글턴 서비스
//
// 왜 서비스로 분리하는가?
//   Supabase 클라이언트는 앱 전체에서 하나의 인스턴스만
//   생성해서 재사용해야 합니다. NestJS의 Injectable을
//   사용하면 DI 컨테이너가 싱글턴으로 관리해줍니다.
//
// 사용법:
//   다른 서비스(UsersService 등)에서 constructor에
//   SupabaseService를 주입받아 this.supabase.client를 사용합니다.
// ══════════════════════════════════════════════════════════

@Injectable()
export class SupabaseService {
  // Supabase 클라이언트 인스턴스 (DB 쿼리에 사용)
  readonly client: SupabaseClient;

  constructor(private readonly configService: ConfigService) {
    const url = this.configService.getOrThrow<string>('SUPABASE_URL');
    // service_role 키: RLS를 우회해서 모든 테이블에 접근 가능
    // anon 키와 달리 서버에서만 사용. 절대 클라이언트에 노출 금지.
    const key = this.configService.getOrThrow<string>('SUPABASE_SERVICE_ROLE_KEY');

    this.client = createClient(url, key);
  }
}
