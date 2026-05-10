import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // POS 전용 블루/네이비 팔레트 (사용자 선택, 2026-05-07).
        // 디자인 구조는 LunchSync 점주앱 가이드(LUNCHSYNC_CODE_GUIDE.md §3) 그대로 — 컬러만 교체.
        primary: {
          DEFAULT: "#2563EB", // royal blue
          dark: "#1E40AF", // navy
          light: "#60A5FA",
          surface: "#EFF6FF",
        },
        ink: {
          900: "#1A1A1A",
          700: "#666666",
          500: "#999999",
        },
        line: {
          divider: "#EEEEEE",
          border: "#DDDDDD",
        },
        bg: {
          page: "#F8F8F8", // backgroundGrey
        },
        state: {
          success: "#27AE60",
          error: "#E74C3C",
          warning: "#F39C12",
        },
        status: {
          paid: "#2563EB",
          preparing: "#F39C12",
          ready: "#FFD23F",
          completed: "#999999",
          cancelled: "#E74C3C",
        },
      },
      fontFamily: {
        // Noto Sans KR(via next/font) → CSS 변수 → fallback
        sans: [
          "var(--font-noto-kr)",
          "Noto Sans KR",
          "Noto Sans",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "sans-serif",
        ],
      },
      // LUNCHSYNC_CODE_GUIDE.md §3.app_text_styles
      fontSize: {
        // [size, lineHeight]
        h1: ["28px", { lineHeight: "1.3", fontWeight: "700" }],
        h2: ["22px", { lineHeight: "1.35", fontWeight: "700" }],
        h3: ["18px", { lineHeight: "1.4", fontWeight: "600" }],
      },
      spacing: {
        // 8px 그리드
        "screen-x": "20px",
      },
      borderRadius: {
        button: "28px",
        card: "12px",
        chip: "20px",
        input: "10px",
        sheet: "20px",
      },
      boxShadow: {
        card: "0 1px 3px rgba(15, 23, 42, 0.04), 0 1px 2px rgba(15, 23, 42, 0.04)",
        elevated: "0 4px 12px rgba(15, 23, 42, 0.08)",
        header: "0 1px 0 rgba(15, 23, 42, 0.04)",
      },
      keyframes: {
        flash: {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.4" },
        },
      },
      animation: {
        flash: "flash 1s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
