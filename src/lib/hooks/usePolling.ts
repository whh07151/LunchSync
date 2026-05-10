"use client";

import { useCallback, useEffect, useRef, useState } from "react";

// 3초 폴링 + 백그라운드 진입 시 중단 + 포그라운드 복귀 시 재요청.
// LUNCHSYNC_SPECIFICATION.md §4 (폴링 생명주기), POS_BUILD_GUIDE.md §7

const DEFAULT_INTERVAL = 3000;

function readEnvInterval(): number {
  const raw = process.env.NEXT_PUBLIC_POLLING_INTERVAL_MS;
  if (!raw) return DEFAULT_INTERVAL;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n >= 500 ? n : DEFAULT_INTERVAL;
}

interface PollingState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  lastUpdatedAt: Date | null;
}

interface UsePollingOptions {
  intervalMs?: number;
  enabled?: boolean;
}

export function usePolling<T>(
  fetcher: () => Promise<T>,
  deps: ReadonlyArray<unknown>,
  options: UsePollingOptions = {}
) {
  const { intervalMs = readEnvInterval(), enabled = true } = options;
  const [state, setState] = useState<PollingState<T>>({
    data: null,
    loading: true,
    error: null,
    lastUpdatedAt: null,
  });

  const fetcherRef = useRef(fetcher);
  fetcherRef.current = fetcher;

  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const inflightRef = useRef<AbortController | null>(null);

  const tick = useCallback(async () => {
    if (inflightRef.current) {
      inflightRef.current.abort();
    }
    const controller = new AbortController();
    inflightRef.current = controller;
    try {
      const data = await fetcherRef.current();
      if (controller.signal.aborted) return;
      setState({ data, loading: false, error: null, lastUpdatedAt: new Date() });
    } catch (e) {
      if (controller.signal.aborted) return;
      const msg = e instanceof Error ? e.message : "조회 실패";
      // NOT_MODIFIED 는 폴링 최적화 케이스 — 데이터 유지하고 에러 무시
      if (msg === "Not Modified") return;
      setState((s) => ({ ...s, loading: false, error: msg }));
    }
  }, []);

  useEffect(() => {
    if (!enabled) return;

    const start = () => {
      tick();
      timerRef.current = setInterval(tick, intervalMs);
    };
    const stop = () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      if (inflightRef.current) {
        inflightRef.current.abort();
        inflightRef.current = null;
      }
    };
    const onVisibility = () => {
      if (document.hidden) {
        stop();
      } else {
        start();
      }
    };

    start();
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      stop();
      document.removeEventListener("visibilitychange", onVisibility);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, intervalMs, ...deps]);

  return { ...state, refetch: tick };
}
