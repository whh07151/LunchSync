"use client";

import { useCallback } from "react";
import { getOrders } from "@/lib/api/pos";
import { usePolling } from "@/lib/hooks/usePolling";
import type { Order, OrderStatus } from "@/lib/types";

export function useOrders(
  restaurantId: string | null,
  status?: OrderStatus,
  enabled = true
) {
  const fetcher = useCallback(async (): Promise<Order[]> => {
    if (!restaurantId) return [];
    return getOrders(restaurantId, status);
  }, [restaurantId, status]);

  return usePolling<Order[]>(fetcher, [restaurantId, status], {
    enabled: enabled && Boolean(restaurantId),
  });
}
