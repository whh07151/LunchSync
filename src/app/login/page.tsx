"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/hooks/useAuth";
import { loginPOS } from "@/lib/api/auth";
import { ApiError } from "@/lib/api/client";

// pos_memo.md §2 / §3 — POS 로그인은 사장앱에서 발급된 고유번호(restaurant_id)
// 단일 입력. 회원가입 없음. 정식 인증 엔드포인트는 백엔드 합의 후 추가.

// 사장앱이 아직 없을 때 UI를 둘러보기 위한 데모 단말 정보.
// week2_jdy_summary.md UUID 규칙(rest_001 = bbbbbbbb-0000-4000-8000-000000000001)을 그대로 사용 →
// 백엔드 시드 스크립트(`backend/scripts/seed-restaurants.ts`)가 돌아간 환경에선 실 데이터까지 자동 연결.
const DEMO = {
  restaurantId: "bbbbbbbb-0000-4000-8000-000000000001",
  name: "데모 단말 (1번)",
};

export default function LoginPage() {
  const router = useRouter();
  const { login } = useAuth();
  const [restaurantId, setRestaurantId] = useState("");
  const [name, setName] = useState("");
  // PIN 입력 (2026-05-12 박검토 후 추가) — 백엔드 POS_PIN 환경변수 설정 시 필수.
  // 빈 값이어도 미설정 환경에서는 발급 성공 (하위 호환).
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // POS 로그인 공통 처리 — 백엔드(POST /pos/login/:restaurantId) 호출 후 토큰 저장.
  // 백엔드가 꺼져있거나 식당이 등록되지 않은 경우엔 토큰 없이 localStorage 만 채우는
  // 폴백으로 동작하여 UI 미리보기는 가능 (기존 동작 보존).
  const performLogin = async (id: string, terminalName: string, pinValue?: string) => {
    setBusy(true);
    setError(null);
    try {
      try {
        const result = await loginPOS(id, terminalName || undefined, pinValue || undefined);
        login({
          restaurantId: result.restaurantId,
          accessToken: result.accessToken,
          user: {
            id: "pos-terminal",
            name: result.restaurantName ?? terminalName ?? "POS 단말",
            role: "POS",
          },
        });
        router.replace("/dashboard");
        return;
      } catch (apiErr) {
        // 에러 분류 (2026-05-12 박검토C 긴급 수정):
        //   - 404 (식당 미등록): UI 미리보기 폴백 허용 — 데모 단말 흐름과 호환
        //   - NETWORK_ERROR (백엔드 다운): 폴백 허용 — 오프라인 모드
        //   - 401/403/400/422 (입력 오류 군): 폴백 금지, 명시적 에러 노출.
        //     예전 버전은 401 도 폴백으로 흘러 토큰 없이 "성공"한 척 → 이후 모든
        //     POS API 가 401 로 깨짐. 사용자가 잘못된 ID 입력한 것을 즉시 알려야 함.
        //   - 5xx: 폴백 금지, 명시적 에러 (서버 장애)
        if (apiErr instanceof ApiError) {
          const isFallbackAllowed =
            apiErr.status === 404 || apiErr.code === "NETWORK_ERROR";
          if (!isFallbackAllowed) {
            setError(
              apiErr.status === 401 || apiErr.status === 403
                ? '식당 고유번호가 잘못되었거나 권한이 없어요. 다시 확인해 주세요.'
                : apiErr.message,
            );
            return;
          }
        }
        // 폴백: 토큰 없이 진입 (백엔드 합의 전 흐름과 동일)
        login({
          restaurantId: id,
          user: {
            id: "pos-terminal",
            name: terminalName || "POS 단말",
            role: "POS",
          },
        });
        router.replace("/dashboard");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "로그인 실패");
    } finally {
      setBusy(false);
    }
  };

  const enterDemo = () => {
    void performLogin(DEMO.restaurantId, DEMO.name, pin.trim());
  };

  const submit = (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    const id = restaurantId.trim();
    if (!id) {
      setError("식당 고유번호를 입력해 주세요.");
      return;
    }
    if (id.length < 4) {
      setError("고유번호 형식이 올바르지 않습니다.");
      return;
    }
    void performLogin(id, name.trim(), pin.trim());
  };

  return (
    <main className="min-h-screen relative overflow-hidden bg-gradient-to-br from-primary-surface via-white to-primary-surface flex items-center justify-center p-screen-x">
      {/* 배경 장식 — LunchSync 온보딩 톤 */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-24 -right-24 h-72 w-72 rounded-full bg-primary/10 blur-3xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-24 -left-24 h-72 w-72 rounded-full bg-primary-light/20 blur-3xl"
      />

      <div className="relative bg-white rounded-card shadow-elevated w-full max-w-md p-8">
        <div className="flex items-center gap-2 mb-1">
          <span className="inline-flex h-9 w-9 rounded-xl bg-primary text-white items-center justify-center font-bold">
            LS
          </span>
          <span className="text-xs font-semibold tracking-wider text-primary-dark uppercase">
            POS Terminal
          </span>
        </div>
        <h1 className="text-h1 text-ink-900 mt-2">LunchSync POS</h1>
        <p className="text-sm text-ink-700 mt-1">매장 카운터/주방용 단말</p>

        <section className="mt-6 bg-primary-surface border border-primary-light/50 rounded-input p-4 text-sm text-ink-700 leading-relaxed">
          <p className="font-semibold text-ink-900 mb-1">회원가입은 따로 없어요</p>
          POS에는 별도 회원가입이 없습니다. 사장님이 <b>사장앱</b>에서 식당을
          등록하시면 <b>고유번호</b>가 발급됩니다. 그 번호를 아래에 입력해 주세요.
        </section>

        <form onSubmit={submit} className="mt-5 space-y-4">
          <Field
            label="식당 고유번호"
            value={restaurantId}
            onChange={setRestaurantId}
            placeholder="예: bbbbbbbb-0000-4000-8000-000000000001"
            hint="사장앱 → 식당 등록 → 고유번호 발급 후 받은 값"
            autoFocus
          />
          <Field
            label="단말 이름 (선택)"
            value={name}
            onChange={setName}
            placeholder="예: 1번 카운터"
            hint="여러 POS를 쓸 때 단말 구분용. 화면 우측 상단에 표시됩니다"
          />
          <Field
            label="PIN (운영 환경)"
            value={pin}
            onChange={setPin}
            placeholder="****"
            hint="관리자에게 받은 4자리 PIN. 개발 환경에서는 비워두세요"
          />

          {error && (
            <div className="text-sm text-state-error bg-red-50 border border-red-200 rounded-input p-3">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={busy}
            className="w-full h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50"
          >
            {busy ? "확인 중…" : "POS 시작"}
          </button>
        </form>

        {/* 사장앱이 준비되기 전 UI 미리보기용 */}
        <div className="mt-5 pt-5 border-t border-line-divider">
          <div className="flex items-baseline justify-between mb-2">
            <p className="text-xs font-semibold text-ink-700">사장앱이 아직 없나요?</p>
            <span className="text-[10px] text-ink-500">개발 전용</span>
          </div>
          <p className="text-[11px] text-ink-500 mb-2.5 leading-relaxed">
            가짜 식당 고유번호로 UI를 둘러볼 수 있습니다. 백엔드 시드가 돌아간
            환경이라면 식당 1번 데이터까지 자동 연결됩니다.
          </p>
          <button
            type="button"
            onClick={enterDemo}
            className="w-full h-10 rounded-button border border-primary-light bg-primary-surface text-primary-dark text-sm font-semibold hover:bg-primary-light/20 transition-colors"
          >
            데모 단말로 시작 →
          </button>
        </div>

        <details className="mt-5 text-xs text-ink-500">
          <summary className="cursor-pointer select-none hover:text-ink-700">
            고유번호를 모르겠어요
          </summary>
          <ol className="mt-2 list-decimal pl-5 space-y-1 leading-relaxed">
            <li>사장앱을 엽니다.</li>
            <li>식당 등록 → 내 업체 선택 → 고유번호 발급 단계 진행.</li>
            <li>발급된 고유번호를 받아서 이 화면에 붙여 넣습니다.</li>
            <li>이미 등록된 매장이라면 사장앱 매장 정보 화면에 표시되어 있습니다.</li>
          </ol>
        </details>

        <p className="text-[11px] text-ink-500 mt-5 leading-relaxed">
          ※ 정식 POS 인증 엔드포인트가 정해지지 않아 현재는 고유번호를 단말에
          저장만 합니다 (백엔드 협의 후 자동 토큰 발급 흐름으로 교체 예정).
        </p>
      </div>
    </main>
  );
}

interface FieldProps {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  hint?: string;
  autoFocus?: boolean;
}

function Field({ label, value, onChange, placeholder, hint, autoFocus }: FieldProps) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-ink-700 mb-1.5">{label}</span>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoFocus={autoFocus}
        spellCheck={false}
        autoComplete="off"
        className="w-full h-11 border border-line-border rounded-input px-3 text-sm placeholder:text-ink-500 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/15 transition-shadow"
      />
      {hint && <span className="block text-[11px] text-ink-500 mt-1">{hint}</span>}
    </label>
  );
}
