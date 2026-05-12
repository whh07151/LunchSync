// ══════════════════════════════════════════════════════════
// 파일 역할: 결제 시뮬레이션 E2E — 토스페이먼츠 SDK v2 결제위젯
//
// 검증 시나리오:
//   1) 결제 API 무토큰 → 401
//   2) 결제 성공 리다이렉트 URL (/payment/success) 렌더 확인 — 쿼리스트링만 통과
//   3) 결제 실패 리다이렉트 URL (/payment/fail) 렌더 확인
//
// 토스 SDK 제약:
//   실제 결제창은 외부 도메인 iframe — Playwright 에서 인증/결제 클릭은 불가.
//   대신 우리 콜백 URL 들이 정상 렌더되고 쿼리 파라미터 처리 흐름이 살아있는지만 확인.
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const screensDir = path.join(__dirname, '..', 'screenshots');
fs.mkdirSync(screensDir, { recursive: true });

test.describe('결제 시뮬 (Payment Mock)', () => {
  test('결제 confirm API 무토큰 → 401', async ({ request }) => {
    const res = await request.post('http://localhost:3000/api/payments/confirm', {
      data: {
        paymentKey: 'test_paymentkey',
        orderId: 'test_orderid',
        amount: 1000,
      },
    });
    expect([401, 403]).toContain(res.status());
  });

  test('성공 콜백 URL — 쿼리스트링 포함해서 정상 렌더', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('pageerror', (err) => consoleErrors.push(err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    // 토스가 리다이렉트할 때 보내는 형식 모사
    await page.goto(
      '/payment/success?paymentKey=test_key&orderId=test_order&amount=12000',
    );
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(3_000);

    await page.screenshot({
      path: path.join(screensDir, '50-payment-success.png'),
      fullPage: true,
    });

    const fatal = consoleErrors.filter(
      (e) =>
        !/kakao|firebase|recaptcha|favicon|manifest|service worker|net::ERR_FAILED|cors|toss/i.test(
          e,
        ),
    );
    expect(fatal, fatal.join('\n')).toEqual([]);
  });

  test('실패 콜백 URL — 쿼리스트링 포함해서 정상 렌더', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('pageerror', (err) => consoleErrors.push(err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.goto(
      '/payment/fail?code=USER_CANCEL&message=%EC%82%AC%EC%9A%A9%EC%9E%90+%EC%B7%A8%EC%86%8C',
    );
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(3_000);

    await page.screenshot({
      path: path.join(screensDir, '51-payment-fail.png'),
      fullPage: true,
    });

    const fatal = consoleErrors.filter(
      (e) =>
        !/kakao|firebase|recaptcha|favicon|manifest|service worker|net::ERR_FAILED|cors|toss/i.test(
          e,
        ),
    );
    expect(fatal, fatal.join('\n')).toEqual([]);
  });
});
