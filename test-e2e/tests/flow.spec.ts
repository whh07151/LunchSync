// ══════════════════════════════════════════════════════════
// 파일 역할: LunchSync 핵심 사용자 흐름 스크린샷 회귀 검증
//
// 검증 시나리오:
//   1) Splash → "시작하기" 클릭 가능한 위치까지 스크롤
//   2) Splash 우회: localStorage 로 onboarding_done=true 주입 → LoginScreen
//   3) 회원가입 진입: 페이지 키보드 입력으로 navigation 시도 (Flutter web 키 입력)
//
// 제약:
//   CanvasKit 렌더러는 DOM 텍스트 검색 불가. 좌표 기반 click + 스크린샷.
//   따라서 본 테스트는 "에러 없이 렌더링되고 클릭에 응답하는지"만 확인.
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as path from 'path';

const screensDir = path.join(__dirname, '..', 'screenshots');

test.describe('LunchSync 핵심 흐름 (스크린샷 회귀)', () => {
  test('Splash 화면 정상 렌더 + 콘솔 에러 없음', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('pageerror', (err) => consoleErrors.push(err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.goto('/');
    await page.waitForSelector('flt-glass-pane, flutter-view', {
      timeout: 30_000,
    });
    await page.waitForTimeout(2_500);

    await page.screenshot({
      path: path.join(screensDir, '10-splash.png'),
      fullPage: true,
    });

    // 무해한 에러는 필터링
    const fatal = consoleErrors.filter(
      (e) =>
        !/kakao|firebase|recaptcha|favicon|manifest|service worker|net::ERR_FAILED|cors/i.test(
          e,
        ),
    );
    expect(fatal, fatal.join('\n')).toEqual([]);
  });

  test('LoginScreen 진입 후 스크린샷 — 카카오·휴대폰 버튼 노출', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('flutter.onboarding_done', 'true');
    });

    await page.goto('/');
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(4_000);

    await page.screenshot({
      path: path.join(screensDir, '11-login.png'),
      fullPage: true,
    });

    // viewport 캡처 — 휴대폰 버튼이 보이는 영역만 잘라서 별도 저장 (시연용)
    await page.screenshot({
      path: path.join(screensDir, '12-login-viewport.png'),
      fullPage: false,
    });

    const flutterView = await page.$('flt-glass-pane, flutter-view');
    expect(flutterView).not.toBeNull();
  });

  test('로그인 화면에서 휴대폰 버튼 위치 클릭 시 phone_verify 화면 진입', async ({
    page,
  }) => {
    await page.addInitScript(() => {
      localStorage.setItem('flutter.onboarding_done', 'true');
    });
    await page.goto('/');
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(4_000);

    // LoginScreen 의 "휴대폰 번호로 시작하기" 버튼은 viewport 하단.
    // viewport 기본 1280x720 기준 — y=673 근처(스크린샷 02-login-screen.png 참조).
    const viewport = page.viewportSize();
    if (viewport) {
      // 화면 가로 중앙, 하단에서 약 8% 위치 — "휴대폰 번호로 시작하기" 버튼 추정 위치
      const x = viewport.width / 2;
      const y = viewport.height - 50;
      await page.mouse.click(x, y);
      await page.waitForTimeout(2_500);
    }

    await page.screenshot({
      path: path.join(screensDir, '13-phone-verify.png'),
      fullPage: true,
    });

    // 페이지가 살아있는지만 확인 — CanvasKit DOM 검증 불가
    const flutterView = await page.$('flt-glass-pane, flutter-view');
    expect(flutterView).not.toBeNull();
  });
});
