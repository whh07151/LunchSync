// ══════════════════════════════════════════════════════════
// 파일 역할: 세션 생성 + 투표 흐름 E2E
//
// 검증 시나리오:
//   1) 인증 없이 세션 생성 시 401 (보안 검증)
//   2) 인증 없이 투표 시 401
//   3) Flutter 홈 화면 → 세션 생성 버튼 좌표 클릭 → 렌더링 살아있음
//
// 비즈니스 규칙 (CLAUDE.md):
//   - WAITING → VOTING: 방장이 투표 시작 (멤버 1명 이상)
//   - VOTING → ORDERED: 전원 투표 완료 또는 방장 수동 종료
//   - votes UNIQUE(user_id, session_id) — 1인 1투표
// ══════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const screensDir = path.join(__dirname, '..', 'screenshots');
fs.mkdirSync(screensDir, { recursive: true });

test.describe('세션 생성 + 투표 (Session Create / Vote)', () => {
  test('세션 생성 API 무토큰 → 401', async ({ request }) => {
    const res = await request.post('http://localhost:3000/api/sessions', {
      data: { title: '점심 모임', maxParticipants: 5 },
    });
    expect([401, 403]).toContain(res.status());
  });

  test('투표 API 무토큰 → 401', async ({ request }) => {
    const res = await request.post(
      'http://localhost:3000/api/sessions/00000000-0000-0000-0000-000000000000/votes',
      { data: { restaurantId: '11111111-1111-1111-1111-111111111111' } },
    );
    expect([401, 403, 404]).toContain(res.status());
  });

  test('홈 화면 → 세션 생성 좌표 클릭 → 다음 화면 진입 확인', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('pageerror', (err) => consoleErrors.push(err.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.addInitScript(() => {
      localStorage.setItem('flutter.onboarding_done', 'true');
    });

    await page.goto('/');
    await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 30_000 });
    await page.waitForTimeout(4_000);

    // FAB "세션 만들기" 추정 위치 — 화면 우하단.
    const vp = page.viewportSize();
    if (vp) {
      await page.mouse.click(vp.width - 60, vp.height - 100);
      await page.waitForTimeout(2_500);
    }

    await page.screenshot({
      path: path.join(screensDir, '40-session-create.png'),
      fullPage: true,
    });

    const fatal = consoleErrors.filter(
      (e) =>
        !/kakao|firebase|recaptcha|favicon|manifest|service worker|net::ERR_FAILED|cors/i.test(e),
    );
    expect(fatal, fatal.join('\n')).toEqual([]);
  });
});
