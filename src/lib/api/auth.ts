import { apiRequest } from "@/lib/api/client";
import type { AuthResult } from "@/lib/types";

// ══════════════════════════════════════════════════════════
// 파일 역할: POS 단말 인증 API 클라이언트
//
// 엔드포인트 (백엔드 매핑):
//   POST /auth/kakao             — 카카오 SSO (보존, 미사용 — 사장앱 흐름용)
//   POST /pos/login/:restaurantId — POS 단말 로그인 (LSPOS 통합 2026-05-12)
// ══════════════════════════════════════════════════════════

// POST /auth/kakao — LUNCHSYNC_DTO.md §2
// POS 로그인 흐름은 loginPOS() 로 옮겨갔고, 본 함수는 카카오 SSO 가 도입될
// 가능성에 대비해 보존만 해둠. 현재 로그인 화면에서는 호출하지 않음.
export async function loginWithKakao(
  kakaoAccessToken: string
): Promise<AuthResult> {
  return apiRequest<AuthResult>("/auth/kakao", {
    method: "POST",
    auth: false,
    body: { kakaoAccessToken },
  });
}

/// POS 로그인 응답 — 백엔드 PosAuthService.login 결과와 매칭.
export interface PosLoginResult {
  accessToken: string;
  restaurantId: string;
  restaurantName: string | null;
  terminalName: string | null;
}

/// POST /pos/login/:restaurantId — POS 단말 로그인.
/// 식당 고유번호가 백엔드 restaurants 테이블에 등록되어 있어야 발급 성공.
/// 성공 시 client.ts 가 이후 모든 요청에 Bearer 헤더 자동 주입.
///
/// PIN (2026-05-12 추가): 백엔드 POS_PIN 환경변수가 설정된 경우 필수.
/// 미설정 환경에서는 빈 값이어도 발급 성공 (하위 호환).
export async function loginPOS(
  restaurantId: string,
  terminalName?: string,
  pin?: string,
): Promise<PosLoginResult> {
  const body: Record<string, string> = {};
  if (terminalName) body.terminalName = terminalName;
  if (pin) body.pin = pin;
  return apiRequest<PosLoginResult>(`/pos/login/${restaurantId}`, {
    method: "POST",
    auth: false,
    body,
  });
}
