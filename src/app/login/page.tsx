"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/hooks/useAuth";
import { loginOwner, registerRestaurant } from "@/lib/api/auth";
import type { RegisterRestaurantPayload } from "@/lib/api/auth";

// 사장 계정(이메일+비번)으로 로그인 → 식당 등록 or 대시보드 진입
// POST /api/pos/login-owner → restaurant 있으면 바로 대시보드
//                           → 없으면 식당 등록 폼 표시
// POST /api/pos/restaurants → 식당 생성 → 대시보드 진입

const CATEGORIES = ["한식", "중식", "일식", "양식", "분식", "카페/디저트", "기타"];

type Step = "login" | "register";

export default function LoginPage() {
  const router = useRouter();
  const { login } = useAuth();

  const [step, setStep] = useState<Step>("login");
  const [userToken, setUserToken] = useState("");

  // 로그인 폼 상태
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  // 식당 등록 폼 상태
  const [form, setForm] = useState<RegisterRestaurantPayload>({
    name: "",
    category: "한식",
    address: "",
    lat: 0,
    lng: 0,
    priceRange: undefined,
    imageUrl: "",
  });

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // ── 로그인 제출 ──────────────────────────────────────
  const submitLogin = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email.trim() || !password) {
      setError("이메일과 비밀번호를 입력해 주세요.");
      return;
    }
    setBusy(true);
    try {
      const result = await loginOwner(email.trim(), password);
      if (result.restaurant) {
        // 식당 있음 → POS 토큰으로 바로 로그인
        login({
          restaurantId: result.restaurant.restaurantId,
          accessToken: result.restaurant.posToken,
          user: {
            id: "pos-terminal",
            name: result.restaurant.restaurantName,
            role: "POS",
          },
        });
        router.replace("/dashboard");
      } else {
        // 식당 없음 → 식당 등록 단계로
        setUserToken(result.userToken);
        setStep("register");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "로그인에 실패했습니다.");
    } finally {
      setBusy(false);
    }
  };

  // ── 식당 등록 제출 ────────────────────────────────────
  const submitRegister = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!form.name.trim() || !form.address.trim()) {
      setError("식당 이름과 주소를 입력해 주세요.");
      return;
    }
    if (!form.lat || !form.lng) {
      setError("위도와 경도를 입력해 주세요.");
      return;
    }
    setBusy(true);
    try {
      const result = await registerRestaurant(userToken, {
        ...form,
        priceRange: form.priceRange || undefined,
        imageUrl: form.imageUrl || undefined,
      });
      login({
        restaurantId: result.id,
        accessToken: result.posToken,
        user: {
          id: "pos-terminal",
          name: result.name,
          role: "POS",
        },
      });
      router.replace("/dashboard");
    } catch (err) {
      setError(err instanceof Error ? err.message : "식당 등록에 실패했습니다.");
    } finally {
      setBusy(false);
    }
  };

  const setField = <K extends keyof RegisterRestaurantPayload>(
    key: K,
    value: RegisterRestaurantPayload[K]
  ) => setForm((f) => ({ ...f, [key]: value }));

  return (
    <main className="min-h-screen relative overflow-hidden bg-gradient-to-br from-primary-surface via-white to-primary-surface flex items-center justify-center p-screen-x">
      <div aria-hidden className="pointer-events-none absolute -top-24 -right-24 h-72 w-72 rounded-full bg-primary/10 blur-3xl" />
      <div aria-hidden className="pointer-events-none absolute -bottom-24 -left-24 h-72 w-72 rounded-full bg-primary-light/20 blur-3xl" />

      <div className="relative bg-white rounded-card shadow-elevated w-full max-w-md p-8">
        <div className="flex items-center gap-2 mb-1">
          <span className="inline-flex h-9 w-9 rounded-xl bg-primary text-white items-center justify-center font-bold text-sm">LS</span>
          <span className="text-xs font-semibold tracking-wider text-primary-dark uppercase">POS Terminal</span>
        </div>

        {step === "login" ? (
          <>
            <h1 className="text-h1 text-ink-900 mt-2">사장님 로그인</h1>
            <p className="text-sm text-ink-700 mt-1">LunchSync 사장 계정으로 로그인하세요</p>

            <form onSubmit={submitLogin} className="mt-6 space-y-4">
              <Field
                label="이메일"
                type="email"
                value={email}
                onChange={setEmail}
                placeholder="owner@example.com"
                autoFocus
              />
              <Field
                label="비밀번호"
                type="password"
                value={password}
                onChange={setPassword}
                placeholder="비밀번호 입력"
              />

              {error && <ErrorBox message={error} />}

              <button
                type="submit"
                disabled={busy}
                className="w-full h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50"
              >
                {busy ? "확인 중…" : "로그인"}
              </button>
            </form>

            <p className="text-[11px] text-ink-500 mt-5 leading-relaxed">
              LunchSync 앱에서 <b>사장(OWNER)</b> 계정으로 가입한 뒤 이 화면에서 로그인하세요.
              로그인 후 식당과 메뉴를 등록하면 손님 앱에 바로 반영됩니다.
            </p>
          </>
        ) : (
          <>
            <h1 className="text-h1 text-ink-900 mt-2">식당 등록</h1>
            <p className="text-sm text-ink-700 mt-1">등록된 식당이 없어요. 식당 정보를 입력해 주세요.</p>

            <form onSubmit={submitRegister} className="mt-6 space-y-4">
              <Field label="식당 이름 *" value={form.name} onChange={(v) => setField("name", v)} placeholder="예: 한솥도시락 강남점" autoFocus />

              <label className="block">
                <span className="block text-xs font-medium text-ink-700 mb-1.5">카테고리 *</span>
                <select
                  value={form.category}
                  onChange={(e) => setField("category", e.target.value)}
                  className="w-full h-11 border border-line-border rounded-input px-3 text-sm focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/15 transition-shadow bg-white"
                >
                  {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </label>

              <Field label="주소 *" value={form.address} onChange={(v) => setField("address", v)} placeholder="예: 서울시 강남구 테헤란로 123" />

              <div className="grid grid-cols-2 gap-3">
                <Field
                  label="위도 *"
                  type="number"
                  value={form.lat === 0 ? "" : String(form.lat)}
                  onChange={(v) => setField("lat", parseFloat(v) || 0)}
                  placeholder="예: 37.5014"
                />
                <Field
                  label="경도 *"
                  type="number"
                  value={form.lng === 0 ? "" : String(form.lng)}
                  onChange={(v) => setField("lng", parseFloat(v) || 0)}
                  placeholder="예: 127.0396"
                />
              </div>

              <p className="text-[11px] text-ink-500 -mt-2">
                위도/경도는 구글맵에서 식당을 검색한 뒤 URL 또는 좌표 복사로 확인할 수 있습니다.
              </p>

              <Field
                label="평균 가격대 (원)"
                type="number"
                value={form.priceRange === undefined ? "" : String(form.priceRange)}
                onChange={(v) => setField("priceRange", v ? parseInt(v, 10) : undefined)}
                placeholder="예: 9000"
              />
              <Field label="대표 이미지 URL" value={form.imageUrl ?? ""} onChange={(v) => setField("imageUrl", v)} placeholder="https://..." />

              {error && <ErrorBox message={error} />}

              <button
                type="submit"
                disabled={busy}
                className="w-full h-12 rounded-button bg-primary text-white font-semibold hover:bg-primary-dark active:scale-[0.99] transition disabled:opacity-50"
              >
                {busy ? "등록 중…" : "식당 등록하고 시작하기"}
              </button>
              <button
                type="button"
                onClick={() => { setStep("login"); setError(null); }}
                className="w-full h-10 rounded-button border border-line-border text-ink-700 text-sm hover:bg-gray-50 transition-colors"
              >
                ← 돌아가기
              </button>
            </form>
          </>
        )}
      </div>
    </main>
  );
}

interface FieldProps {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  autoFocus?: boolean;
  type?: string;
}

function Field({ label, value, onChange, placeholder, autoFocus, type = "text" }: FieldProps) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-ink-700 mb-1.5">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoFocus={autoFocus}
        spellCheck={false}
        autoComplete="off"
        step={type === "number" ? "any" : undefined}
        className="w-full h-11 border border-line-border rounded-input px-3 text-sm placeholder:text-ink-500 focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/15 transition-shadow"
      />
    </label>
  );
}

function ErrorBox({ message }: { message: string }) {
  return (
    <div className="text-sm text-state-error bg-red-50 border border-red-200 rounded-input p-3">
      {message}
    </div>
  );
}
