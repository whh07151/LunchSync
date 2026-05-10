import "./globals.css";
import type { Metadata, Viewport } from "next";
import { Noto_Sans_KR } from "next/font/google";

// LUNCHSYNC_CODE_GUIDE §3 (Noto Sans 한글 최적화) — Next.js 정적 폰트로 로딩
const notoSansKr = Noto_Sans_KR({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-noto-kr",
  display: "swap",
});

export const metadata: Metadata = {
  title: "LunchSync POS",
  description: "LunchSync 주방·카운터용 POS 웹",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#2563EB",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko" className={notoSansKr.variable}>
      <body className="font-sans antialiased bg-bg-page text-ink-900">{children}</body>
    </html>
  );
}
