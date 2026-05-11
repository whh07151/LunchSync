// ══════════════════════════════════════════════════════════
// 파일 역할: LunchSync 웹 빌드 스모크 테스트 (CanvasKit 호환)
//
// 제약:
//   Flutter web 기본 렌더러는 CanvasKit 이라 텍스트가 DOM 이 아닌 캔버스에 그려짐.
//   → DOM 텍스트 셀렉터로는 검증 불가. 대신:
//     1) Flutter view host (flt-glass-pane/flutter-view) 가 렌더링됐는지
//     2) 치명적 콘솔 에러가 없는지
//     3) 스크린샷 저장 후 수동 검토
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

// 스크린샷 저장 경로
const screensDir = path.join(__dirname, '..', 'screenshots');
fs.mkdirSync(screensDir, { recursive: true });

test.describe('LunchSync 웹 스모크', () => {
  test('첫 화면이 정상 로드되고 Flutter view 가 마운트된다', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('pageerror', (err) =>
      consoleErrors.push(`pageerror: ${err.message}`),
    );
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(`console.error: ${msg.text()}`);
      }
    });

    await page.goto('/');

    // Flutter view host 가 보일 때까지 대기 (CanvasKit 빌드 기준)
    await page.waitForSelector(
      'flt-glass-pane, flutter-view, flt-scene-host',
      { timeout: 30_000 },
    );

    // 렌더링 안정화 대기 (Splash → Login 전환까지)
    await page.waitForTimeout(3_000);

    // 스크린샷 저장 — 수동 검토용
    await page.screenshot({
      path: path.join(screensDir, '01-first-screen.png'),
      fullPage: true,
    });

    // 콘솔 에러 필터링 — 외부 SDK 비활성 환경에서 발생하는 무해한 에러는 허용
    const ignorePatterns = [
      'kakao',
      'Kakao',
      'firebase',
      'Firebase',
      'reCAPTCHA',
      'favicon',
      'manifest',
      'service worker',
      'ServiceWorker',
      'net::ERR_FAILED',  // 외부 리소스 차단 시
      'CORS',             // 외부 API 차단 시
    ];
    const fatal = consoleErrors.filter(
      (e) => !ignorePatterns.some((p) => e.toLowerCase().includes(p.toLowerCase())),
    );

    if (fatal.length > 0) {
      console.log('---- 발견된 콘솔 에러 ----');
      fatal.forEach((e) => console.log(e));
      console.log('-------------------------');
    }
    expect(fatal, fatal.join('\n')).toEqual([]);
  });

  test('백엔드 API 가 응답한다', async ({ request }) => {
    // /api 루트 — AppController.getHello() 호출
    const res = await request.get('http://localhost:3000/api/');
    expect(res.status()).toBe(200);
  });

  test('카카오 로그인 화면 SDK 가 page context 에 로드돼 있다', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // window.Kakao 가 정의돼 있는지 (web/index.html 에 script 태그로 로드)
    const hasKakao = await page.evaluate(() => {
      // @ts-ignore
      return typeof window.Kakao !== 'undefined';
    });
    expect(hasKakao, 'window.Kakao 미정의 — web/index.html 의 카카오 SDK 스크립트 확인 필요').toBe(true);
  });
});
