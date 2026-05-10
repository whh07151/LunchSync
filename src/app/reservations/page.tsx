"use client";

import { useMemo, useState } from "react";
import AppShell from "@/components/AppShell";
import { useAuth } from "@/lib/hooks/useAuth";
import {
  useReservations,
  type Reservation,
  type ReservationKind,
} from "@/lib/hooks/useReservations";
import { formatTimeAgo } from "@/lib/utils/format";

// pos_memo §6-3, §8-2 — 웨이팅 / 예약 관리 (백엔드 미구현 → localStorage)
export default function ReservationsPage() {
  const auth = useAuth();
  const { list, ready, stats, add, updateStatus, remove } = useReservations(
    auth.restaurantId
  );

  const [tab, setTab] = useState<ReservationKind>("WAITING");
  const [showAdd, setShowAdd] = useState(false);

  const filtered = useMemo(
    () => list.filter((r) => r.kind === tab && r.status === "OPEN"),
    [list, tab]
  );
  const closed = useMemo(
    () => list.filter((r) => r.kind === tab && r.status !== "OPEN"),
    [list, tab]
  );

  return (
    <AppShell>
      <div className="max-w-[1200px] mx-auto px-screen-x py-6 space-y-5">
        <div className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-h1 text-ink-900">웨이팅·예약</h1>
            <p className="text-sm text-ink-500 mt-1">
              대기 손님과 예약을 관리합니다
              <span className="ml-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-chip border border-line-border bg-white text-[10px] font-medium text-ink-700">
                데모 · 로컬 저장
              </span>
            </p>
          </div>
          <button
            type="button"
            onClick={() => setShowAdd(true)}
            className="h-10 px-4 rounded-button bg-primary text-white text-sm font-semibold hover:bg-primary-dark"
          >
            + 추가
          </button>
        </div>

        {/* 탭 */}
        <div className="flex gap-2">
          <TabButton
            active={tab === "WAITING"}
            onClick={() => setTab("WAITING")}
            label="웨이팅"
            count={stats.waiting}
          />
          <TabButton
            active={tab === "RESERVATION"}
            onClick={() => setTab("RESERVATION")}
            label="예약"
            count={stats.reservations}
          />
        </div>

        {!ready ? (
          <p className="py-10 text-center text-sm text-ink-500">불러오는 중…</p>
        ) : filtered.length === 0 ? (
          <div className="bg-white border border-line-divider rounded-card p-10 text-center text-sm text-ink-500">
            대기 중인 {tab === "WAITING" ? "웨이팅" : "예약"}이 없습니다
          </div>
        ) : (
          <ul className="bg-white border border-line-divider rounded-card shadow-card divide-y divide-line-divider">
            {filtered.map((r) => (
              <ReservationRow
                key={r.id}
                r={r}
                onSeat={() => updateStatus(r.id, "SEATED")}
                onCancel={() => updateStatus(r.id, "CANCELLED")}
                onRemove={() => remove(r.id)}
              />
            ))}
          </ul>
        )}

        {closed.length > 0 && (
          <details className="bg-white border border-line-divider rounded-card overflow-hidden">
            <summary className="px-5 py-3 cursor-pointer text-sm font-semibold text-ink-700 hover:bg-gray-50">
              완료/취소 내역 ({closed.length})
            </summary>
            <ul className="divide-y divide-line-divider">
              {closed.map((r) => (
                <ReservationRow
                  key={r.id}
                  r={r}
                  onRemove={() => remove(r.id)}
                  closedView
                />
              ))}
            </ul>
          </details>
        )}

        <p className="text-xs text-ink-500">
          ※ 백엔드 웨이팅·예약 모델이 합의된 후 실시간 동기화로 교체 예정.
        </p>
      </div>

      {showAdd && (
        <ReservationFormModal
          kind={tab}
          onClose={() => setShowAdd(false)}
          onSubmit={(v) => {
            add(v);
            setShowAdd(false);
          }}
        />
      )}
    </AppShell>
  );
}

function TabButton({
  active,
  onClick,
  label,
  count,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  count: number;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={
        "h-10 px-4 rounded-chip text-sm font-semibold border inline-flex items-center gap-1.5 " +
        (active
          ? "bg-primary text-white border-primary"
          : "bg-white text-ink-700 border-line-border hover:bg-gray-50")
      }
    >
      {label}
      <span
        className={
          "tabular-nums text-[11px] " + (active ? "opacity-90" : "text-ink-500")
        }
      >
        {count}
      </span>
    </button>
  );
}

function ReservationRow({
  r,
  onSeat,
  onCancel,
  onRemove,
  closedView = false,
}: {
  r: Reservation;
  onSeat?: () => void;
  onCancel?: () => void;
  onRemove?: () => void;
  closedView?: boolean;
}) {
  return (
    <li className="px-5 py-3 flex items-center justify-between gap-3">
      <div className="min-w-0">
        <p className="text-sm font-bold text-ink-900">
          {r.customerName}{" "}
          <span className="font-normal text-ink-700">· {r.partySize}명</span>
        </p>
        <p className="text-xs text-ink-500 mt-0.5">
          {r.kind === "RESERVATION" && r.scheduledAt
            ? `예약 ${new Date(r.scheduledAt).toLocaleString("ko-KR")}`
            : `등록 ${formatTimeAgo(r.createdAt)}`}
          {r.note ? ` · ${r.note}` : ""}
          {closedView && (
            <span className="ml-1 text-ink-700">
              · {r.status === "SEATED" ? "착석 완료" : "취소됨"}
            </span>
          )}
        </p>
      </div>
      <div className="flex items-center gap-1">
        {!closedView && onSeat && (
          <button
            type="button"
            onClick={onSeat}
            className="h-9 px-3 rounded-chip bg-primary text-white text-xs font-semibold hover:bg-primary-dark"
          >
            착석 처리
          </button>
        )}
        {!closedView && onCancel && (
          <button
            type="button"
            onClick={onCancel}
            className="h-9 px-3 rounded-chip border border-line-border bg-white text-ink-700 text-xs font-medium hover:bg-gray-50"
          >
            취소
          </button>
        )}
        {onRemove && (
          <button
            type="button"
            onClick={onRemove}
            className="h-9 w-9 rounded-full text-ink-500 hover:bg-red-50 hover:text-state-error inline-flex items-center justify-center"
            aria-label="삭제"
          >
            ×
          </button>
        )}
      </div>
    </li>
  );
}

function ReservationFormModal({
  kind,
  onClose,
  onSubmit,
}: {
  kind: ReservationKind;
  onClose: () => void;
  onSubmit: (v: {
    kind: ReservationKind;
    customerName: string;
    partySize: number;
    scheduledAt?: string;
    note?: string;
  }) => void;
}) {
  const [name, setName] = useState("");
  const [partySize, setPartySize] = useState<number>(2);
  const [scheduledAt, setScheduledAt] = useState("");
  const [note, setNote] = useState("");

  const valid =
    name.trim().length > 0 &&
    partySize > 0 &&
    (kind === "WAITING" || scheduledAt.length > 0);

  return (
    <div
      className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-sheet sm:rounded-card w-full max-w-md p-6 shadow-elevated"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-h2 text-ink-900 mb-4">
          {kind === "WAITING" ? "웨이팅 추가" : "예약 추가"}
        </h2>
        <div className="space-y-3">
          <Field label="손님 이름/닉네임">
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
              placeholder="홍길동"
            />
          </Field>
          <Field label="인원">
            <input
              type="number"
              inputMode="numeric"
              value={partySize}
              onChange={(e) =>
                setPartySize(Math.max(1, Number(e.target.value) || 1))
              }
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
            />
          </Field>
          {kind === "RESERVATION" && (
            <Field label="예약 일시">
              <input
                type="datetime-local"
                value={scheduledAt}
                onChange={(e) => setScheduledAt(e.target.value)}
                className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
              />
            </Field>
          )}
          <Field label="메모 (선택)">
            <input
              type="text"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary"
              placeholder="창가 자리 요청 등"
            />
          </Field>
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
                kind,
                customerName: name.trim(),
                partySize,
                scheduledAt:
                  kind === "RESERVATION"
                    ? new Date(scheduledAt).toISOString()
                    : undefined,
                note: note.trim() || undefined,
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
