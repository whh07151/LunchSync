import { Module } from '@nestjs/common';
import { SupabaseModule } from '../supabase/supabase.module';
import { FriendsController } from './friends.controller';
import { FriendsService } from './friends.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 친구 모듈 정의 (controller/service 묶음)
//
// app.module.ts 의 imports 배열에 FriendsModule 등록 필요.
// ══════════════════════════════════════════════════════════

@Module({
  imports: [SupabaseModule],
  controllers: [FriendsController],
  providers: [FriendsService],
  exports: [FriendsService],
})
export class FriendsModule {}
