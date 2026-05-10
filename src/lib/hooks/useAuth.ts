"use client";

import { useCallback, useEffect, useState } from "react";
import {
  STORAGE_KEYS,
  clearSession,
  getAccessToken,
  getRestaurantId,
  setAccessToken,
  setRestaurantId,
} from "@/lib/api/client";
import type { AuthUser } from "@/lib/types";

interface AuthState {
  ready: boolean;
  accessToken: string | null;
  restaurantId: string | null;
  user: AuthUser | null;
}

function readUser(): AuthUser | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(STORAGE_KEYS.user);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as AuthUser;
  } catch {
    return null;
  }
}

function writeUser(u: AuthUser | null): void {
  if (typeof window === "undefined") return;
  if (u) {
    window.localStorage.setItem(STORAGE_KEYS.user, JSON.stringify(u));
  } else {
    window.localStorage.removeItem(STORAGE_KEYS.user);
  }
}

export function useAuth() {
  const [state, setState] = useState<AuthState>({
    ready: false,
    accessToken: null,
    restaurantId: null,
    user: null,
  });

  useEffect(() => {
    setState({
      ready: true,
      accessToken: getAccessToken(),
      restaurantId: getRestaurantId(),
      user: readUser(),
    });
  }, []);

  const login = useCallback(
    (params: {
      restaurantId: string;
      accessToken?: string | null;
      user?: AuthUser | null;
    }) => {
      // pos_memo.md: POS는 고유번호(restaurantId)로 식별. 정식 인증 엔드포인트는 백엔드 합의 미정.
      // accessToken/user는 백엔드에서 POS 로그인 흐름이 정해지면 채워짐.
      setAccessToken(params.accessToken ?? null);
      setRestaurantId(params.restaurantId);
      writeUser(params.user ?? null);
      setState({
        ready: true,
        accessToken: params.accessToken ?? null,
        restaurantId: params.restaurantId,
        user: params.user ?? null,
      });
    },
    []
  );

  const logout = useCallback(() => {
    clearSession();
    setState({ ready: true, accessToken: null, restaurantId: null, user: null });
  }, []);

  const updateRestaurantId = useCallback((id: string) => {
    setRestaurantId(id);
    setState((s) => ({ ...s, restaurantId: id }));
  }, []);

  return { ...state, login, logout, updateRestaurantId };
}
