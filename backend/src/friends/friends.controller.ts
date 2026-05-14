import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { IsEmail, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FriendsService } from './friends.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 친구 관계 HTTP 엔드포인트 (CU-08 보강)
//
// 엔드포인트:
//   POST   /api/friends                 — 친구 추가 (이메일로)
//   GET    /api/friends                 — 내 친구 목록
//   DELETE /api/friends/:friendUserId   — 친구 삭제 (양방향)
//
// 인증:
//   모든 라우트 JwtAuthGuard. req.user.userId 가 친구 관계의 주인.
// ══════════════════════════════════════════════════════════

type AuthedRequest = { user: { userId: string } };

class AddFriendDto {
  @IsEmail() @IsNotEmpty() email: string;
}

@Controller('friends')
@UseGuards(JwtAuthGuard)
export class FriendsController {
  constructor(private readonly friendsService: FriendsService) {}

  // ── POST /api/friends — 친구 추가 ─────────────────────
  @Post()
  async addFriend(@Req() req: AuthedRequest, @Body() dto: AddFriendDto) {
    const result = await this.friendsService.addFriendByEmail(
      req.user.userId,
      dto.email,
    );
    return { success: true, data: result };
  }

  // ── GET /api/friends — 내 친구 목록 ───────────────────
  @Get()
  async listFriends(@Req() req: AuthedRequest) {
    const result = await this.friendsService.listFriends(req.user.userId);
    return { success: true, data: result };
  }

  // ── DELETE /api/friends/:friendUserId — 친구 삭제 ─────
  @Delete(':friendUserId')
  async removeFriend(
    @Req() req: AuthedRequest,
    @Param('friendUserId') friendUserId: string,
  ) {
    const result = await this.friendsService.removeFriend(
      req.user.userId,
      friendUserId,
    );
    return { success: true, data: result };
  }
}
