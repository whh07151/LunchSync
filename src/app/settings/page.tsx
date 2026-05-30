"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import AppShell from "@/components/AppShell";
import { useAuth } from "@/lib/hooks/useAuth";
import { useShopStatus } from "@/lib/hooks/useShopStatus";
import { setRestaurantId, STORAGE_KEYS } from "@/lib/api/client";

// pos_memo §6-3 — 설정. 식당 고유번호 변경, 단말 이름 변경, 영업 상태,
// 캐시 초기화(메뉴/매출/좌석).
export default function SettingsPage() {
  const router = useRouter();
  const auth = useAuth();
  const { open: shopOpen, setShopOpen } = useShopStatus(auth.restaurantId);

  const [newRestaurantId, setNewRestaurantId] = useState(
    auth.restaurantId ?? ""
  );
  const [newName, setNewName] = useState(auth.user?.name ?? "");
  const [savedMessage, setSavedMessage] = useState<string | null>(null);

  // saveTerminal — 단말 정보 저장 (2026-05-12 박검토C 긴급 수정).
  //   기존 버그: auth.login({restaurantId, user}) 만 호출 → useAuth.login 안에서
  //   setAccessToken(params.accessToken ?? null) 가 실행되어 **현재 로그인 토큰 증발**
  //   → 이후 모든 /pos/* API 가 401 로 깨짐.
  //   수정: accessToken: auth.accessToken 명시 전달로 기존 POS 토큰 보존.
  const saveTerminal = () => {
    const id = newRestaurantId.trim();
    const name = newName.trim() || "POS 단말";
    if (!id) return;
    auth.login({
      restaurantId: id,
      accessToken: auth.accessToken, // 기존 POS JWT 유지 — 토큰 증발 방지
      user: {
        id: auth.user?.id ?? "pos-terminal",
        name,
        role: "POS",
      },
    });
    setRestaurantId(id);
    setSavedMessage("저장되었습니다");
    setTimeout(() => setSavedMessage(null), 2000);
  };

  const clearStore = (label: string, prefix: string) => {
    if (!auth.restaurantId) return;
    if (
      !window.confirm(
        `${label} 데이터를 이 단말에서 삭제하시겠어요? 되돌릴 수 없습니다.`
      )
    )
      return;
    const key = `${prefix}_${auth.restaurantId}`;
    window.localStorage.removeItem(key);
    setSavedMessage(`${label} 데이터를 비웠습니다 (새로고침 시 반영)`);
    setTimeout(() => setSavedMessage(null), 2500);
  };

  const logoutAndClear = () => {
    if (
      !window.confirm(
        "이 단말의 모든 POS 데이터(좌석/메뉴/매출/예약 + 로그인)를 삭제하고 로그아웃합니다. 계속할까요?"
      )
    )
      return;
    if (auth.restaurantId) {
      [
        `ls_pos_seats_${auth.restaurantId}`,
        `ls_pos_menu_${auth.restaurantId}`,
        `ls_pos_sales_${auth.restaurantId}`,
        `ls_pos_reservations_${auth.restaurantId}`,
        `ls_pos_open_${auth.restaurantId}`,
      ].forEach((k) => window.localStorage.removeItem(k));
    }
    Object.values(STORAGE_KEYS).forEach((k) =>
      window.localStorage.removeItem(k)
    );
    auth.logout();
    router.replace("/login");
  };

  return (
    <AppShell>
      <div className="max-w-2xl mx-auto px-screen-x py-6 space-y-6">
        <div>
          <h1 className="text-h1 text-ink-900">설정</h1>
          <p className="text-sm text-ink-500 mt-1">
            단말 식별 정보와 데이터 관리
          </p>
        </div>

        {savedMessage && (
          <div className="rounded-card bg-state-success/10 border border-state-success/30 px-4 py-2 text-sm text-state-success">
            {savedMessage}
          </div>
        )}

        {/* 단말 정보 */}
        <Section title="단말 정보">
          <Field label="식당 고유번호 (restaurantId)">
            <input
              type="text"
              value={newRestaurantId}
              onChange={(e) => setNewRestaurantId(e.target.value)}
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm font-mono focus:outline-none focus:border-primary"
              placeholder="bbbbbbbb-0000-4000-8000-000000000001"
            />
          </Field>
          <Field label="단말 이름">
            <input
              type="text"
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
              placeholder="1번 카운터"
            />
          </Field>
          <button
            type="button"
            onClick={saveTerminal}
            className="h-11 px-5 rounded-button bg-primary text-white text-sm font-semibold hover:bg-primary-dark"
          >
            저장
          </button>
        </Section>

        {/* 영업 상태 */}
        <Section title="영업 상태">
          <p className="text-sm text-ink-700">
            현재 상태:{" "}
            <span
              className={
                "font-semibold " +
                (shopOpen ? "text-emerald-700" : "text-ink-500")
              }
            >
              {shopOpen ? "영업중" : "마감"}
            </span>
          </p>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setShopOpen(true)}
              disabled={shopOpen}
              className="h-10 px-4 rounded-button bg-state-success text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50"
            >
              영업 시작
            </button>
            <button
              type="button"
              onClick={() => setShopOpen(false)}
              disabled={!shopOpen}
              className="h-10 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50 disabled:opacity-50"
            >
              영업 마감
            </button>
          </div>
          <p className="text-[11px] text-ink-500">
            상단바 영업중 칩을 직접 클릭해서도 토글할 수 있어요.
          </p>
        </Section>

        {/* 데이터 관리 */}
        <Section title="데이터 관리 (개발용)">
          <p className="text-sm text-ink-700">
            POS의 좌석/메뉴/매출/예약 데이터는 모두 이 단말 localStorage에
            저장됩니다. 백엔드 합의 후 서버 동기화로 교체될 임시 저장소입니다.
          </p>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <ClearButton
              label="좌석"
              onClick={() => clearStore("좌석", "ls_pos_seats")}
            />
            <ClearButton
              label="메뉴"
              onClick={() => clearStore("메뉴", "ls_pos_menu")}
            />
            <ClearButton
              label="매출"
              onClick={() => clearStore("매출", "ls_pos_sales")}
            />
            <ClearButton
              label="예약"
              onClick={() => clearStore("예약", "ls_pos_reservations")}
            />
          </div>
          <button
            type="button"
            onClick={logoutAndClear}
            className="mt-2 h-11 px-4 rounded-button border border-red-200 bg-red-50 text-state-error text-sm font-semibold hover:bg-red-100"
          >
            전체 초기화 + 로그아웃
          </button>
        </Section>

        {/* 빠른 링크 */}
        <Section title="화면 모드">
          <p className="text-sm text-ink-700">
            대형 모니터·태블릿용 풀스크린 화면 빠른 진입.
          </p>
          <div className="flex gap-2 flex-wrap">
            <a
              href="/kitchen"
              className="h-10 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50 inline-flex items-center"
            >
              주방 모드
            </a>
            <a
              href="/board"
              className="h-10 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50 inline-flex items-center"
            >
              호출 보드
            </a>
          </div>
        </Section>
      </div>
    </AppShell>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="bg-white border border-line-divider rounded-card shadow-card p-5 space-y-3">
      <h2 className="text-base font-bold text-ink-900">{title}</h2>
      {children}
    </section>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-ink-700 mb-1">{label}</span>
      {children}
    </label>
  );
}

function ClearButton({
  label,
  onClick,
}: {
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="h-10 rounded-input border border-line-border bg-white text-ink-700 text-xs font-medium hover:bg-gray-50"
    >
      {label} 비우기
    </button>
  );
}
