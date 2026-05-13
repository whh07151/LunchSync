// ══════════════════════════════════════════════════════════
// 파일 역할: 캡스톤 시연용 정식 캡처 (회원가입 / 카카오 로그인 / 결제)
//
// 출력 위치: test-e2e/screenshots/capstone/
//   01-login-screen.png            로그인 화면 (카카오 버튼)
//   02-signup-empty.png             회원가입 빈 폼 (손님 기본)
//   03-signup-customer-filled.png   회원가입 손님 입력 완료
//   04-signup-owner-toggled.png     역할 OWNER 토글 → 상호명/사업자번호 노출
//   05-signup-owner-filled.png      사장 가입 입력 완료
//   06-email-otp-screen.png         이메일 OTP 입력 화면 (시뮬)
//   10-kakao-button-focus.png       카카오 버튼 클릭 직전 (강조)
//   11-kakao-click-aftermath.png    카카오 버튼 클릭 후 (외부 페이지로 떠나기 직전)
//   20-payment-success.png          결제 성공 콜백 화면
//   21-payment-fail.png             결제 실패 콜백 화면
//   22-payment-401.png              무토큰 결제 API → 401 응답 시각화 X (CLI 로그용)
//
// CanvasKit 제약:
//   DOM 텍스트 검색 불가. 좌표 클릭 + 스크린샷으로만 진행.
//   카카오 동의 페이지는 외부 도메인이라 봇 차단 가능 — 진입 시도까지만 캡처.
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const captureDir = path.join(__dirname, '..', 'screenshots', 'capstone');
fs.mkdirSync(captureDir, { recursive: true });

// LoginScreen 진입을 위한 공통 초기화
async function gotoLoginScreen(page: import('@playwright/test').Page) {
  await page.addInitScript(() => {
    localStorage.setItem('flutter.onboarding_done', 'true');
  });
  await page.goto('/');
  await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
  await page.waitForTimeout(5_000);
}

test.describe('캡스톤 시연 캡처', () => {
  // ── 01. 로그인 화면 ─────────────────────────────────
  test('01 로그인 화면 (카카오 버튼)', async ({ page }) => {
    await gotoLoginScreen(page);
    await page.screenshot({
      path: path.join(captureDir, '01-login-screen.png'),
      fullPage: true,
    });
    const flutterView = await page.$('flt-glass-pane, flutter-view');
    expect(flutterView).not.toBeNull();
  });

  // ── 02~05. 회원가입 흐름 ────────────────────────────
  test('02~05 회원가입 흐름 (손님 + 사장 토글)', async ({ page }) => {
    await gotoLoginScreen(page);

    // 로그인 화면 하단의 "회원가입" 버튼 영역을 좌표로 탭
    // Flutter CanvasKit 이라 직접 click 가능 (이벤트가 캔버스로 전달됨)
    const viewport = page.viewportSize();
    const w = viewport?.width ?? 1280;
    const h = viewport?.height ?? 720;

    // 회원가입 링크는 보통 화면 하단 중앙
    await page.mouse.click(w / 2, h * 0.92);
    await page.waitForTimeout(2_500);

    await page.screenshot({
      path: path.join(captureDir, '02-signup-empty.png'),
      fullPage: true,
    });

    // 빈 폼에서 키보드로 이메일 입력 — Flutter 의 TextField 는 포커스가 필요
    // 좌표 클릭 후 type 으로 입력. (실패해도 캡처는 진행)
    try {
      await page.mouse.click(w / 2, h * 0.32);
      await page.waitForTimeout(400);
      await page.keyboard.type('demo@lunchsync.test', { delay: 30 });

      await page.mouse.click(w / 2, h * 0.42);
      await page.waitForTimeout(400);
      await page.keyboard.type('Demo12345!', { delay: 30 });

      await page.mouse.click(w / 2, h * 0.5);
      await page.waitForTimeout(400);
      await page.keyboard.type('Demo12345!', { delay: 30 });

      await page.mouse.click(w / 2, h * 0.58);
      await page.waitForTimeout(400);
      await page.keyboard.type('홍길동', { delay: 30 });

      await page.waitForTimeout(1_000);
      await page.screenshot({
        path: path.join(captureDir, '03-signup-customer-filled.png'),
        fullPage: true,
      });
    } catch (e) {
      console.log('[signup-customer-filled] 입력 단계 실패 — 캡처만 진행:', e);
    }

    // 역할을 OWNER 로 토글 — 라디오 위치는 폼 상단 어딘가
    try {
      await page.mouse.click(w * 0.7, h * 0.22);
      await page.waitForTimeout(800);
      await page.screenshot({
        path: path.join(captureDir, '04-signup-owner-toggled.png'),
        fullPage: true,
      });

      // 상호명 / 사업자번호 입력 시뮬
      await page.mouse.click(w / 2, h * 0.7);
      await page.waitForTimeout(400);
      await page.keyboard.type('데모 식당', { delay: 30 });

      await page.mouse.click(w / 2, h * 0.78);
      await page.waitForTimeout(400);
      await page.keyboard.type('123-45-67890', { delay: 30 });
      await page.waitForTimeout(800);

      await page.screenshot({
        path: path.join(captureDir, '05-signup-owner-filled.png'),
        fullPage: true,
      });
    } catch (e) {
      console.log('[signup-owner] 토글/입력 단계 실패 — 캡처만 진행:', e);
    }
  });

  // ── 06. 이메일 OTP 진입 (URL 직접 진입 또는 시뮬) ───
  test('06 이메일 OTP 화면 캡처 시도', async ({ page }) => {
    // 이메일 OTP 는 회원가입 완료 후에만 자연스럽게 나오지만,
    // 시연용으로 캡처가 필요하므로 회원가입 후 화면 도달 또는 빈 화면 캡처.
    await gotoLoginScreen(page);
    const viewport = page.viewportSize();
    const w = viewport?.width ?? 1280;
    const h = viewport?.height ?? 720;

    // 회원가입 진입
    await page.mouse.click(w / 2, h * 0.92);
    await page.waitForTimeout(2_500);

    // OTP 진입을 위한 강제 시도는 회원가입 완료가 필요 — 현 상태 캡처만 저장
    await page.screenshot({
      path: path.join(captureDir, '06-email-otp-screen.png'),
      fullPage: true,
    });
  });

  // ── 10~11. 카카오 로그인 진입 시도 ───────────────────
  test('10~11 카카오 버튼 클릭 흐름', async ({ page }) => {
    await gotoLoginScreen(page);
    const viewport = page.viewportSize();
    const w = viewport?.width ?? 1280;
    const h = viewport?.height ?? 720;

    // 카카오 버튼은 보통 로그인 화면 상단/중앙
    await page.screenshot({
      path: path.join(captureDir, '10-kakao-button-focus.png'),
      fullPage: true,
    });

    // 클릭은 새 탭 또는 외부 페이지 이동을 유발 — 무시하고 캡처만
    try {
      const [maybePopup] = await Promise.all([
        page.waitForEvent('popup', { timeout: 3_000 }).catch(() => null),
        page.mouse.click(w / 2, h * 0.4),
      ]);
      await page.waitForTimeout(2_500);

      if (maybePopup) {
        // 카카오 동의 페이지가 새 창으로 열린 경우
        await maybePopup.waitForLoadState('domcontentloaded', { timeout: 8_000 }).catch(() => {});
        await maybePopup.screenshot({
          path: path.join(captureDir, '11-kakao-click-aftermath.png'),
          fullPage: true,
        });
      } else {
        await page.screenshot({
          path: path.join(captureDir, '11-kakao-click-aftermath.png'),
          fullPage: true,
        });
      }
    } catch (e) {
      console.log('[kakao-flow] 카카오 진입 실패 — 현재 화면 캡처:', e);
      await page.screenshot({
        path: path.join(captureDir, '11-kakao-click-aftermath.png'),
        fullPage: true,
      });
    }
  });

  // ── 20~21. 결제 성공/실패 콜백 ───────────────────────
  test('20 결제 성공 콜백 화면', async ({ page }) => {
    await page.goto('/payment/success?paymentKey=demo_key&orderId=demo_order&amount=12000');
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(3_500);
    await page.screenshot({
      path: path.join(captureDir, '20-payment-success.png'),
      fullPage: true,
    });
  });

  test('21 결제 실패 콜백 화면', async ({ page }) => {
    await page.goto(
      '/payment/fail?code=USER_CANCEL&message=%EC%82%AC%EC%9A%A9%EC%9E%90+%EC%B7%A8%EC%86%8C',
    );
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(3_500);
    await page.screenshot({
      path: path.join(captureDir, '21-payment-fail.png'),
      fullPage: true,
    });
  });
});
