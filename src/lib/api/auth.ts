import { apiRequest } from "@/lib/api/client";
import type { AuthResult } from "@/lib/types";

export interface OwnerLoginResult {
  userToken: string;
  restaurant: {
    posToken: string;
    restaurantId: string;
    restaurantName: string;
  } | null;
}

export interface RegisterRestaurantPayload {
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  priceRange?: number;
  imageUrl?: string;
}

export interface RegisterRestaurantResult {
  id: string;
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  imageUrl: string | null;
  posToken: string;
}

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

/// POST /pos/login/:restaurantId — POS 단말 로그인 (레거시, 기존 호환용).
export async function loginPOS(
  restaurantId: string,
  terminalName?: string
): Promise<PosLoginResult> {
  return apiRequest<PosLoginResult>(`/pos/login/${restaurantId}`, {
    method: "POST",
    auth: false,
    body: terminalName ? { terminalName } : {},
  });
}

/// POST /pos/login-owner — 사장 이메일+비번으로 LSPOS 로그인.
/// 성공 시: { userToken, restaurant? }
///   restaurant 있으면 posToken 포함 → 바로 대시보드 진입 가능.
///   restaurant 없으면 null → 식당 등록 화면으로 안내.
export async function loginOwner(
  email: string,
  password: string
): Promise<OwnerLoginResult> {
  return apiRequest<OwnerLoginResult>("/pos/login-owner", {
    method: "POST",
    auth: false,
    body: { email, password },
  });
}

/// POST /pos/restaurants — 사장 계정으로 식당 등록.
/// userToken(USER JWT)을 Authorization 헤더에 직접 전달.
export async function registerRestaurant(
  userToken: string,
  payload: RegisterRestaurantPayload
): Promise<RegisterRestaurantResult> {
  const baseUrl = (process.env.NEXT_PUBLIC_BACKEND_BASE_URL ?? "http://localhost:3000/api").replace(/\/$/, "");
  const res = await fetch(`${baseUrl}/pos/restaurants`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${userToken}`,
    },
    body: JSON.stringify(payload),
    cache: "no-store",
  });
  const json = await res.json() as { success: boolean; data: RegisterRestaurantResult };
  if (!res.ok || !json.success) throw new Error("식당 등록 실패");
  return json.data;
}
