import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';

@Injectable()
export class SessionAccessService {
  constructor(private readonly supabase: SupabaseService) {}

  async assertMember(
    sessionId: string,
    userId: string | undefined,
  ): Promise<void> {
    if (!userId) {
      throw new UnauthorizedException('사용자 인증 정보가 없습니다.');
    }

    const { data, error } = await this.supabase.client
      .from('session_members')
      .select('user_id')
      .eq('session_id', sessionId)
      .eq('user_id', userId)
      .maybeSingle();

    // 세션 존재 여부와 멤버 여부를 같은 응답으로 처리해 UUID 열거를 줄인다.
    if (error || !data) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }
  }
}
