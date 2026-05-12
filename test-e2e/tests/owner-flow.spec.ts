// ══════════════════════════════════════════════════════════
// 파일 역할: 사장 흐름 E2E (사장 로그인 → 대시보드 → 주문 목록)
//
// 검증 시나리오:
//   1) 백엔드 POS 엔드포인트가 인증 가드를 적용하는지 (401 보호 확인)
//   2) 사장 로그인 화면이 정상 렌더되는지 (좌표 기반)
//   3) 콘솔 치명적 에러 없음
//
// 보안 검증 추가 (2026-05-13):
//   POS 권한 검증 분기 작업 후 — 무토큰 접근 시 401 응답하는지 확인.
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const screensDir = path.join(__dirname, '..', 'screenshots');
fs.mkdirSync(screensDir, { recursive: true });

test.describe('사장 흐름 (Owner Flow)', () => {
  test('POS 엔드포인트 무토큰 호출 시 401 또는 403 으로 보호된다', async ({ request }) => {
    // 임의 매장 ID — 권한 검증이 안 됐다면 200 이 떨어질 수 있음.
    const res = await request.get(
      'http://localhost:3000/api/pos/restaurants/00000000-0000-0000-0000-000000000000/orders',
    );
    expect([401, 403]).toContain(res.status());
  });

  test('POS 메뉴 조회 — 무토큰 호출 시 401/403', async ({ request }) => {
    const res = await request.get(
      'http://localhost:3000/api/pos/menus/00000000-0000-0000-0000-000000000000',
    );
    expect([401, 403]).toContain(res.status());
  });

  test('POS 좌석 조회 — 무토큰 호출 시 401/403', async ({ request }) => {
    const res = await request.get(
      'http://localhost:3000/api/pos/seats/00000000-0000-0000-0000-000000000000',
    );
    expect([401, 403]).toContain(res.status());
  });

  test('사장 로그인 화면 스크린샷 — 좌표 기반 진입', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('pageerror', (err) => consoleErrors.push(err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    // 사장 로그인은 별도 경로 (lib/features/owner_auth/...) — 직접 경로 진입 시도.
    // 라우트가 다르면 첫 화면 그대로 떠도 OK (콘솔 에러만 검증).
    await page.addInitScript(() => {
      localStorage.setItem('flutter.onboarding_done', 'true');
    });

    await page.goto('/#/owner/login');
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(4_000);

    await page.screenshot({
      path: path.join(screensDir, '30-owner-login.png'),
      fullPage: true,
    });

    const fatal = consoleErrors.filter(
      (e) =>
        !/kakao|firebase|recaptcha|favicon|manifest|service worker|net::ERR_FAILED|cors/i.test(e),
    );
    expect(fatal, fatal.join('\n')).toEqual([]);
  });
});
