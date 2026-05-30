"use client";

// ══════════════════════════════════════════════════════════
// 파일 역할: 대시보드 "사장님 오늘의 한 줄" 입력 카드 (WOW#1)
//
// 시연 시나리오:
//   1. 사장이 LSPOS 대시보드 진입 → 이 카드가 영업 정보 영역 옆에 노출
//   2. "비 오니까 얼큰순두부 강추 🌧" 입력 후 "저장" 버튼 클릭
//   3. 손님 앱 홈 새로고침 → AI 추천 카드 상단에 노란 띠 + 인용구
//
// 입력 규칙:
//   · 200자 이하 (서버 동일 검증)
//   · 빈 문자열 저장 → null 로 전달돼 노출 중단
//
// 백엔드 연동:
//   · 화면 진입 시 GET /restaurants/:id 로 기존 한 줄 조회 (todaysNote)
//   · 저장 시 PATCH /pos/restaurants/:id/todays-note 호출
//   · 401/네트워크 에러는 빨간 안내, 성공 시 초록 토스트 + 새 값 반영
//
// 한국어 주석 / 한국어 UI 카피 — 시연 시 사장이 직접 확인할 화면이므로
// 톤은 친근(존댓말)으로 유지.
// ══════════════════════════════════════════════════════════

import { useCallback, useEffect, useState } from "react";
import { ApiError } from "@/lib/api/client";
import {
  getRestaurantSummary,
  updateTodaysNote,
} from "@/lib/api/restaurant";

interface TodaysNoteCardProps {
  /** POS 로그인된 매장 ID — null 이면 로딩 placeholder */
  restaurantId: string | null;
  /** auth 준비 완료 플래그 — false 면 fetch 보류 */
  ready: boolean;
}

const MAX_LEN = 200;

export default function TodaysNoteCard({
  restaurantId,
  ready,
}: TodaysNoteCardProps) {
  // ── 입력 상태 ────────────────────────────────────────
  // value: textarea 의 현재 입력값.
  // saved: 마지막으로 서버에 저장된 값(또는 GET 결과). 변경 감지에 사용.
  const [value, setValue] = useState<string>("");
  const [saved, setSaved] = useState<string | null>(null);

  // ── 통신 상태 ────────────────────────────────────────
  const [loading, setLoading] = useState<boolean>(false);
  const [saving, setSaving] = useState<boolean>(false);
  // success: 저장 직후 1.8초간 노출되는 초록 토스트.
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // ── 진입 시 1회 조회 ─────────────────────────────────
  // restaurantId 가 바뀔 때마다 재조회 (다중 매장 운영 가정).
  useEffect(() => {
    if (!ready || !restaurantId) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    void getRestaurantSummary(restaurantId)
      .then((r) => {
        if (cancelled) return;
        const initial = r.todaysNote ?? "";
        setValue(initial);
        setSaved(r.todaysNote ?? null);
      })
      .catch((e) => {
        if (cancelled) return;
        const msg =
          e instanceof ApiError
            ? `식당 정보를 불러오지 못했어요 (${e.code})`
            : "식당 정보를 불러오지 못했어요";
        setError(msg);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [ready, restaurantId]);

  // ── 저장 핸들러 ──────────────────────────────────────
  // trim 결과가 빈 문자열이면 명시적으로 null 로 전달 (DB 도 NULL 로 정리).
  // 성공 시 saved/value 모두 새 값으로 동기화 + 토스트.
  const handleSave = useCallback(async () => {
    if (!restaurantId || saving) return;
    setSaving(true);
    setError(null);
    setSuccess(null);
    try {
      const normalized = value.trim().length === 0 ? null : value.trim();
      const result = await updateTodaysNote(restaurantId, normalized);
      setSaved(result.todaysNote);
      setValue(result.todaysNote ?? "");
      setSuccess(
        normalized === null
          ? "오늘의 한 줄을 비웠어요"
          : "오늘의 한 줄을 저장했어요 ✨",
      );
      // 1.8초 후 자동 사라짐 — 별도 cleanup 은 unmount 시 자동 GC.
      window.setTimeout(() => setSuccess(null), 1800);
    } catch (e) {
      if (e instanceof ApiError) {
        if (e.status === 401) {
          setError("로그인이 만료됐어요. 다시 로그인해주세요.");
        } else if (e.status === 400) {
          setError(e.message ?? "200자를 넘었어요. 조금 줄여주세요.");
        } else {
          setError(`저장에 실패했어요 (${e.code})`);
        }
      } else {
        setError("저장에 실패했어요. 네트워크를 확인해주세요.");
      }
    } finally {
      setSaving(false);
    }
  }, [restaurantId, saving, value]);

  // ── 비우기 단축 버튼 ─────────────────────────────────
  // 빈 문자열로 저장 호출 — 명시적 null 저장과 동일 효과.
  const handleClear = useCallback(() => {
    setValue("");
  }, []);

  // ── 변경 여부 ────────────────────────────────────────
  // trim 후 saved 와 비교 — "한 칸 공백만 다른" 변경은 저장 불활성.
  const trimmedValue = value.trim();
  const savedTrim = (saved ?? "").trim();
  const dirty = trimmedValue !== savedTrim;
  const tooLong = value.length > MAX_LEN;
  const canSave = !saving && !loading && dirty && !tooLong;

  // ── 렌더 ─────────────────────────────────────────────
  return (
    <section
      className="bg-white border border-line-divider rounded-card shadow-card p-5 space-y-3"
      aria-label="사장님 오늘의 한 줄"
    >
      <header className="flex items-center gap-2">
        <span aria-hidden className="text-xl">
          👨‍🍳
        </span>
        <h2 className="text-base font-bold text-ink-900">사장님 한 줄</h2>
        <span className="text-[11px] text-ink-500">
          손님 추천 카드 상단에 그대로 보여요
        </span>
      </header>

      {loading ? (
        <p className="text-sm text-ink-500">불러오는 중...</p>
      ) : (
        <>
          <textarea
            value={value}
            onChange={(e) => setValue(e.target.value)}
            disabled={saving || !restaurantId}
            maxLength={MAX_LEN + 50 /* 사용자 입력 여유 — 검증은 따로 */}
            rows={2}
            placeholder='예) "비 오니까 얼큰순두부 강추 🌧"'
            className={
              "w-full resize-y rounded-card border px-3 py-2 text-sm text-ink-900 " +
              "placeholder:text-ink-500 focus:outline-none focus:ring-2 " +
              (tooLong
                ? "border-state-error focus:ring-red-200"
                : "border-line-divider focus:ring-primary-light")
            }
          />

          <div className="flex items-center justify-between gap-3">
            <span
              className={
                "text-[11px] tabular-nums " +
                (tooLong ? "text-state-error font-semibold" : "text-ink-500")
              }
            >
              {value.length} / {MAX_LEN}자
              {tooLong && " · 200자를 넘었어요"}
            </span>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={handleClear}
                disabled={saving || value.length === 0}
                className="px-3 py-1.5 text-xs rounded-card border border-line-divider text-ink-700 disabled:opacity-40 hover:bg-gray-50"
              >
                비우기
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={!canSave}
                className={
                  "px-4 py-1.5 text-xs font-semibold rounded-card " +
                  (canSave
                    ? "bg-primary-dark text-white hover:opacity-90"
                    : "bg-gray-200 text-gray-500 cursor-not-allowed")
                }
              >
                {saving ? "저장 중..." : dirty ? "저장" : "변경 없음"}
              </button>
            </div>
          </div>

          {/* 저장된 값 미리보기 — 손님에게 보이는 모양 그대로 */}
          {savedTrim.length > 0 && (
            <div className="mt-1 p-3 rounded-card border border-[#FFE082] bg-[#FFF3CD] text-sm text-ink-900">
              <span className="font-semibold mr-1">👨‍🍳 오늘:</span>
              {savedTrim}
            </div>
          )}

          {/* 토스트 영역 */}
          {success && (
            <p className="text-xs text-emerald-700 font-semibold">{success}</p>
          )}
          {error && (
            <p className="text-xs text-state-error font-semibold">{error}</p>
          )}
        </>
      )}
    </section>
  );
}
