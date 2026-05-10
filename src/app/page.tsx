"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/hooks/useAuth";

export default function HomePage() {
  const auth = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!auth.ready) return;
    router.replace(auth.restaurantId ? "/dashboard" : "/login");
  }, [auth.ready, auth.restaurantId, router]);

  return (
    <main className="min-h-screen flex items-center justify-center text-ink-500 text-sm">
      이동 중…
    </main>
  );
}
