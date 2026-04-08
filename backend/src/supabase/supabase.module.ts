import { Global, Module } from '@nestjs/common';
import { SupabaseService } from './supabase.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: Supabase 모듈
//
// @Global() 데코레이터를 사용하는 이유:
//   SupabaseService는 Users, Sessions, Orders 등
//   거의 모든 모듈에서 필요합니다. @Global()을 붙이면
//   각 모듈마다 imports에 추가할 필요 없이
//   AppModule에 한 번만 등록하면 전역에서 주입 가능합니다.
// ══════════════════════════════════════════════════════════

@Global()
@Module({
  providers: [SupabaseService],
  exports: [SupabaseService], // 다른 모듈에서 주입받을 수 있도록 export
})
export class SupabaseModule {}
