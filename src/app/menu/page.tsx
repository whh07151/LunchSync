"use client";

import { useMemo, useState } from "react";
import AppShell from "@/components/AppShell";
import { useAuth } from "@/lib/hooks/useAuth";
import { useMenu, type MenuItem } from "@/lib/hooks/useMenu";
import { formatPrice } from "@/lib/utils/format";

// pos_memo §4 (POS 권한), §6-3 사이드바 "메뉴 관리".
// 메뉴 추가/가격 수정/품절 토글/삭제. 백엔드 API 미구현 → localStorage(useMenu).
export default function MenuPage() {
  const auth = useAuth();
  const {
    items,
    ready,
    categories,
    addItem,
    updateItem,
    deleteItem,
    toggleSoldOut,
    resetToDemo,
  } = useMenu(auth.restaurantId);

  const [activeCategory, setActiveCategory] = useState<string>("전체");
  const [editing, setEditing] = useState<MenuItem | null>(null);
  const [showAdd, setShowAdd] = useState(false);

  const filtered = useMemo(() => {
    if (activeCategory === "전체") return items;
    return items.filter((m) => m.category === activeCategory);
  }, [items, activeCategory]);

  return (
    <AppShell>
      <div className="max-w-[1400px] mx-auto px-screen-x py-6 space-y-5">
        <div className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-h1 text-ink-900">메뉴 관리</h1>
            <p className="text-sm text-ink-500 mt-1">
              메뉴와 가격을 관리합니다 · 변경 사항은 좌석 주문 화면에 즉시 반영
              <span className="ml-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-chip border border-line-border bg-white text-[10px] font-medium text-ink-700">
                데모 · 로컬 저장
              </span>
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setShowAdd(true)}
              className="h-10 px-4 rounded-button bg-primary text-white text-sm font-semibold hover:bg-primary-dark"
            >
              + 메뉴 추가
            </button>
            <button
              type="button"
              onClick={() => {
                if (window.confirm("메뉴를 데모 기본값으로 초기화하시겠어요?")) {
                  resetToDemo();
                }
              }}
              className="h-10 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50"
            >
              초기화
            </button>
          </div>
        </div>

        {/* 카테고리 탭 */}
        <div className="flex gap-1.5 overflow-x-auto pb-1">
          {categories.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => setActiveCategory(c)}
              className={
                "shrink-0 px-3 py-1.5 rounded-chip text-sm font-semibold border " +
                (activeCategory === c
                  ? "bg-primary text-white border-primary"
                  : "bg-white text-ink-700 border-line-border hover:bg-gray-50")
              }
            >
              {c}
            </button>
          ))}
        </div>

        {!ready ? (
          <p className="py-10 text-center text-sm text-ink-500">불러오는 중…</p>
        ) : filtered.length === 0 ? (
          <div className="bg-white border border-line-divider rounded-card p-10 text-center text-sm text-ink-500">
            {activeCategory === "전체"
              ? "등록된 메뉴가 없습니다"
              : `'${activeCategory}' 카테고리에 메뉴가 없습니다`}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {filtered.map((m) => (
              <article
                key={m.id}
                className={
                  "rounded-card border shadow-card p-4 flex items-start justify-between gap-3 " +
                  (m.soldOut
                    ? "bg-gray-50 border-line-divider opacity-70"
                    : "bg-white border-line-divider")
                }
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <h3 className="text-base font-bold text-ink-900 truncate">
                      {m.name}
                    </h3>
                    {m.soldOut && (
                      <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-chip bg-state-error text-white">
                        품절
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-ink-500 mt-0.5">{m.category}</p>
                  <p className="text-lg font-extrabold text-primary-dark mt-2 tabular-nums">
                    {formatPrice(m.price)}
                  </p>
                </div>
                <div className="flex flex-col gap-1.5 shrink-0">
                  <button
                    type="button"
                    onClick={() => setEditing(m)}
                    className="h-8 px-2.5 rounded-chip border border-line-border bg-white text-xs font-medium text-ink-700 hover:bg-gray-50"
                  >
                    수정
                  </button>
                  <button
                    type="button"
                    onClick={() => toggleSoldOut(m.id)}
                    className={
                      "h-8 px-2.5 rounded-chip text-xs font-medium border " +
                      (m.soldOut
                        ? "bg-state-success text-white border-state-success hover:opacity-90"
                        : "bg-white text-ink-700 border-line-border hover:bg-gray-50")
                    }
                  >
                    {m.soldOut ? "판매 재개" : "품절"}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      if (window.confirm(`'${m.name}' 메뉴를 삭제할까요?`)) {
                        deleteItem(m.id);
                      }
                    }}
                    className="h-8 px-2.5 rounded-chip text-xs font-medium border border-red-200 text-state-error hover:bg-red-50"
                  >
                    삭제
                  </button>
                </div>
              </article>
            ))}
          </div>
        )}

        <p className="text-xs text-ink-500">
          ※ 메뉴/가격은 이 단말 localStorage에 저장됩니다. 백엔드{" "}
          <code className="font-mono">PATCH /pos/menus/:id</code> 합의 후 동기화됨.
        </p>
      </div>

      {showAdd && (
        <MenuFormModal
          title="메뉴 추가"
          initial={{ name: "", price: 0, category: "기타" }}
          onClose={() => setShowAdd(false)}
          onSubmit={(v) => {
            addItem(v);
            setShowAdd(false);
          }}
        />
      )}
      {editing && (
        <MenuFormModal
          title="메뉴 수정"
          initial={{
            name: editing.name,
            price: editing.price,
            category: editing.category,
          }}
          onClose={() => setEditing(null)}
          onSubmit={(v) => {
            updateItem(editing.id, v);
            setEditing(null);
          }}
        />
      )}
    </AppShell>
  );
}

function MenuFormModal({
  title,
  initial,
  onClose,
  onSubmit,
}: {
  title: string;
  initial: { name: string; price: number; category: string };
  onClose: () => void;
  onSubmit: (v: { name: string; price: number; category: string }) => void;
}) {
  const [name, setName] = useState(initial.name);
  const [price, setPrice] = useState<number | "">(initial.price);
  const [category, setCategory] = useState(initial.category);

  const valid =
    name.trim().length > 0 && typeof price === "number" && price >= 0;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-sheet sm:rounded-card w-full max-w-md p-6 shadow-elevated"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-h2 text-ink-900 mb-4">{title}</h2>
        <div className="space-y-3">
          <FormField label="이름">
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
              placeholder="예: 김치찌개"
            />
          </FormField>
          <FormField label="가격 (원)">
            <input
              type="number"
              inputMode="numeric"
              value={price === "" ? "" : price}
              onChange={(e) => {
                const v = e.target.value;
                setPrice(v === "" ? "" : Math.max(0, Number(v)));
              }}
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary tabular-nums"
              placeholder="6500"
            />
          </FormField>
          <FormField label="카테고리">
            <input
              type="text"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
              placeholder="도시락 / 찌개 / 면 / 분식 / 음료 등"
            />
          </FormField>
        </div>
        <div className="mt-5 flex gap-2 justify-end">
          <button
            type="button"
            onClick={onClose}
            className="h-11 px-4 rounded-button border border-line-border bg-white text-ink-700 text-sm font-medium hover:bg-gray-50"
          >
            취소
          </button>
          <button
            type="button"
            disabled={!valid}
            onClick={() =>
              onSubmit({
                name: name.trim(),
                price: typeof price === "number" ? price : 0,
                category: category.trim() || "기타",
              })
            }
            className="h-11 px-5 rounded-button bg-primary text-white text-sm font-semibold hover:bg-primary-dark disabled:opacity-50"
          >
            저장
          </button>
        </div>
      </div>
    </div>
  );
}

function FormField({
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
