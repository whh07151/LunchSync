// 신규 주문 진입 시 짧은 비프음. 외부 의존 없이 WebAudio로 합성.
// 주방 환경에서 시각만으로 부족하므로 사용 (POS_BUILD_GUIDE.md §8)

let ctx: AudioContext | null = null;

function ensureContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (ctx) return ctx;
  const W = window as unknown as { AudioContext?: typeof AudioContext };
  const Ctor = W.AudioContext;
  if (!Ctor) return null;
  ctx = new Ctor();
  return ctx;
}

export function playBeep(freq = 880, durationMs = 180): void {
  const audio = ensureContext();
  if (!audio) return;
  try {
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = "sine";
    osc.frequency.value = freq;
    gain.gain.value = 0.0001;
    osc.connect(gain);
    gain.connect(audio.destination);

    const now = audio.currentTime;
    gain.gain.exponentialRampToValueAtTime(0.2, now + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + durationMs / 1000);

    osc.start(now);
    osc.stop(now + durationMs / 1000 + 0.05);
  } catch {
    // 브라우저 정책으로 사용자 제스처 전엔 막힐 수 있음 — 무시
  }
}

export function playNewOrderChime(): void {
  playBeep(880, 150);
  setTimeout(() => playBeep(1175, 180), 160);
}

export function playReadyChime(): void {
  playBeep(660, 180);
  setTimeout(() => playBeep(990, 180), 180);
  setTimeout(() => playBeep(1320, 220), 360);
}
