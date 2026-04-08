import { Module } from '@nestjs/common';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';
import { AuthModule } from '../auth/auth.module';

// ══════════════════════════════════════════════════════════
// 파일 역할: 유저 모듈
//
// AuthModule을 import하는 이유:
//   JwtAuthGuard가 AuthModule에서 export되기 때문.
//   UsersController의 @UseGuards(JwtAuthGuard)가 동작하려면
//   이 모듈이 JwtAuthGuard를 알고 있어야 함.
// ══════════════════════════════════════════════════════════

@Module({
  imports: [AuthModule],
  controllers: [UsersController],
  providers: [UsersService],
})
export class UsersModule {}
