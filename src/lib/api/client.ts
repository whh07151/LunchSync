// 공용 fetch 래퍼 — JWT 자동 첨부, 공통 응답 포맷 처리
// LUNCHSYNC_DTO.md §1 (공통 응답 구조)

import type { ApiResponse } from "@/lib/types";

export const STORAGE_KEYS = {
  accessToken: "ls_pos_access_token",
  restaurantId: "ls_pos_restaurant_id",
  user: "ls_pos_user",
} as const;

export class ApiError extends Error {
  code: string;
  status: number;
  constructor(message: string, code: string, status: number) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

function getBaseUrl(): string {
  const url = process.env.NEXT_PUBLIC_BACKEND_BASE_URL;
  if (!url || url.length === 0) {
    return "http://localhost:3000/api";
  }
  return url;
}

export function getAccessToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(STORAGE_KEYS.accessToken);
}

export function setAccessToken(token: string | null): void {
  if (typeof window === "undefined") return;
  if (token) {
    window.localStorage.setItem(STORAGE_KEYS.accessToken, token);
  } else {
    window.localStorage.removeItem(STORAGE_KEYS.accessToken);
  }
}

export function getRestaurantId(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(STORAGE_KEYS.restaurantId);
}

export function setRestaurantId(id: string | null): void {
  if (typeof window === "undefined") return;
  if (id) {
    window.localStorage.setItem(STORAGE_KEYS.restaurantId, id);
  } else {
    window.localStorage.removeItem(STORAGE_KEYS.restaurantId);
  }
}

export function clearSession(): void {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(STORAGE_KEYS.accessToken);
  window.localStorage.removeItem(STORAGE_KEYS.restaurantId);
  window.localStorage.removeItem(STORAGE_KEYS.user);
}

interface RequestOptions {
  method?: "GET" | "POST" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, string | number | undefined>;
  signal?: AbortSignal;
  // JWT 주입 여부. 로그인 같은 공개 엔드포인트는 false.
  auth?: boolean;
}

function buildUrl(path: string, query?: RequestOptions["query"]): string {
  const base = getBaseUrl().replace(/\/$/, "");
  const cleanPath = path.startsWith("/") ? path : `/${path}`;
  const url = `${base}${cleanPath}`;
  if (!query) return url;
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query)) {
    if (v === undefined || v === null || v === "") continue;
    params.set(k, String(v));
  }
  const qs = params.toString();
  return qs ? `${url}?${qs}` : url;
}

export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {}
): Promise<T> {
  const { method = "GET", body, query, signal, auth = true } = options;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (auth) {
    const token = getAccessToken();
    if (token) headers["Authorization"] = `Bearer ${token}`;
  }

  let res: Response;
  try {
    res = await fetch(buildUrl(path, query), {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal,
      cache: "no-store",
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "네트워크 오류";
    throw new ApiError(msg, "NETWORK_ERROR", 0);
  }

  // 304 — 데이터 변경 없음 (폴링 최적화). 호출자가 별도 처리하도록 throw 대신 빈 객체 반환은 위험하므로 별도 에러로.
  if (res.status === 304) {
    throw new ApiError("Not Modified", "NOT_MODIFIED", 304);
  }

  let parsed: unknown = null;
  const text = await res.text();
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new ApiError("응답 파싱 실패", "PARSE_ERROR", res.status);
    }
  }

  if (!res.ok) {
    const errBody = parsed as Partial<ApiResponse<unknown>> | null;
    if (errBody && "error" in errBody && errBody.error) {
      throw new ApiError(errBody.error.message, errBody.error.code, res.status);
    }
    throw new ApiError(
      `요청 실패 (${res.status})`,
      res.status === 401 ? "UNAUTHORIZED" : "HTTP_ERROR",
      res.status
    );
  }

  const body2 = parsed as ApiResponse<T> | null;
  if (!body2) {
    throw new ApiError("빈 응답", "EMPTY_BODY", res.status);
  }
  if (!body2.success) {
    throw new ApiError(body2.error.message, body2.error.code, res.status);
  }
  return body2.data;
}
