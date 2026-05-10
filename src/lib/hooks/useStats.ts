"use client";

import { useCallback } from "react";
import { getOrderStats } from "@/lib/api/pos";
import { usePolling } from "@/lib/hooks/usePolling";
import type { OrderStats } from "@/lib/types";

const ZERO: OrderStats = {
  total: 0,
  pending: 0,
  paid: 0,
  preparing: 0,
  ready: 0,
  completed: 0,
  cancelled: 0,
  totalRevenue: 0,
};

export function useOrderStats(restaurantId: string | null, enabled = true) {
  const fetcher = useCallback(async (): Promise<OrderStats> => {
    if (!restaurantId) return ZERO;
    return getOrderStats(restaurantId);
  }, [restaurantId]);

  return usePolling<OrderStats>(fetcher, [restaurantId], {
    enabled: enabled && Boolean(restaurantId),
    intervalMs: 5000,
  });
}
