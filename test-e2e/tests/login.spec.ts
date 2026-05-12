// ══════════════════════════════════════════════════════════
// 파일 역할: LoginScreen 진입 + UI 렌더링 검증
//
// 진입 트릭:
//   Flutter shared_preferences 는 웹에서 localStorage 를 사용한다.
//   key prefix 는 "flutter." 이므로 "flutter.onboarding_done" = "true"
//   를 미리 주입하면 스플래시 건너뛰고 LoginScreen 으로 바로 진입.
//
// 검증:
//   - 로그인 화면이 렌더링되고 카카오/휴대폰 버튼이 보이는지 스크린샷 확인
//   - 회원가입 화면 진입까지 시도
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as path from 'path';

test.describe('LunchSync 로그인 화면', () => {
  test('LoginScreen 으로 바로 진입 후 스크린샷 저장', async ({ page }) => {
    // 첫 방문 시 localStorage 가 비어 있으므로, init script 로 미리 주입
    await page.addInitScript(() => {
      // Flutter 의 shared_preferences 가 web 에서 localStorage 사용 — prefix "flutter."
      localStorage.setItem('flutter.onboarding_done', 'true');
    });

    await page.goto('/');
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });

    // Splash 건너뛰고 LoginScreen 으로 진입할 시간 확보
    await page.waitForTimeout(4_000);

    await page.screenshot({
      path: path.join(__dirname, '..', 'screenshots', '02-login-screen.png'),
      fullPage: true,
    });

    // 페이지 자체는 정상이라고만 검증 — DOM 텍스트는 CanvasKit 이라 비어 있음
    const flutterView = await page.$('flt-glass-pane, flutter-view');
    expect(flutterView).not.toBeNull();
  });
});
