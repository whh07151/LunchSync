import { apiRequest } from "@/lib/api/client";
import type { AuthResult } from "@/lib/types";

// POST /auth/kakao — LUNCHSYNC_DTO.md §2
// POS 로그인 방식이 백엔드 합의 미정이라 우선 카카오 토큰 흐름을 그대로 사용.
// 점포 ID/PW 발급으로 변경되면 여기 함수 시그니처만 교체.
export async function loginWithKakao(
  kakaoAccessToken: string
): Promise<AuthResult> {
  return apiRequest<AuthResult>("/auth/kakao", {
    method: "POST",
    auth: false,
    body: { kakaoAccessToken },
  });
}
