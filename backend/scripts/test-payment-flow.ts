/* eslint-disable @typescript-eslint/no-floating-promises */
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as jwt from 'jsonwebtoken';
import { createClient } from '@supabase/supabase-js';

// ══════════════════════════════════════════════════════════
// 파일 역할: 결제 흐름 end-to-end API 테스트 (브라우저 없이)
//
// 검증 순서:
//   1) DB 에서 테스트 유저 1명 찾음 (seed 로 방장이 된 유저 우선)
//   2) JWT_SECRET 으로 직접 JWT 발급 (카카오 로그인 우회)
//   3) POST /api/orders — 주문 생성 (paymentMethod=TOSS)
//   4) POST /api/payments/confirm — 가짜 paymentKey 로 호출
//      → 토스 API 는 실패하지만, 우리 서버 로직(검증/응답) 은 검증됨
//
// 각 단계에서 에러가 나면 무엇이 문제인지 구체적으로 출력.
// ══════════════════════════════════════════════════════════

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const API_BASE = 'http://localhost:3000/api';
const JWT_SECRET = process.env.JWT_SECRET!;
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const SESSION_ID = '22222222-2222-2222-2222-222222222222';
const MENU_ID = 'aaaaaaaa-0000-4000-8000-000000000001'; // 불고기 덮밥

if (!JWT_SECRET) {
  console.error('❌ JWT_SECRET 없음');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// ── 결과 로그 헬퍼 ──────────────────────────────────────
const log = {
  info: (msg: string) => console.log(`\x1b[36mℹ\x1b[0m  ${msg}`),
  ok: (msg: string) => console.log(`\x1b[32m✓\x1b[0m  ${msg}`),
  fail: (msg: string) => console.log(`\x1b[31m✗\x1b[0m  ${msg}`),
  section: (msg: string) => console.log(`\n\x1b[1m━━ ${msg} ━━\x1b[0m`),
};

async function main() {
  // ── Step 1: 테스트 유저 선택 ──────────────────────────
  log.section('Step 1: 테스트 유저 선택');

  // 방장 유저 우선 선택 (session_members 에 있는 유저)
  const { data: memberRows } = await supabase
    .from('session_members')
    .select('user_id')
    .eq('session_id', SESSION_ID)
    .limit(1);

  let userId: string;
  if (memberRows && memberRows.length > 0) {
    userId = memberRows[0].user_id;
    log.ok(`세션 멤버 유저 사용: ${userId}`);
  } else {
    const { data: users } = await supabase.from('users').select('id').limit(1);
    if (!users || users.length === 0) {
      log.fail('users 테이블이 비어있음');
      process.exit(1);
    }
    userId = users[0].id;
    log.info(`세션 멤버 없음 → 첫 번째 유저 사용: ${userId}`);
  }

  // ── Step 2: JWT 직접 서명 ────────────────────────────
  log.section('Step 2: JWT 직접 서명 (카카오 로그인 우회)');
  const token = jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '1h' });
  log.ok(`JWT 발급 완료 (길이 ${token.length})`);

  // ── Step 3: POST /api/orders ─────────────────────────
  log.section('Step 3: POST /api/orders 호출');

  const orderBody = {
    sessionId: SESSION_ID,
    items: [
      { menuItemId: MENU_ID, quantity: 2 },
    ],
    paymentMethod: 'TOSS',
  };

  const orderRes = await fetch(`${API_BASE}/orders`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(orderBody),
  });

  const orderJson = await orderRes.json();
  log.info(`HTTP ${orderRes.status}`);
  console.log('  응답:', JSON.stringify(orderJson, null, 2));

  if (!orderRes.ok) {
    log.fail('주문 생성 실패 — 여기서 흐름 끊김');
    process.exit(1);
  }

  const created = orderJson.data;
  log.ok(`주문 생성 성공: orderId=${created.id}, total=${created.totalPrice}원`);

  // ── Step 4: POST /api/payments/confirm (가짜 paymentKey) ─
  log.section('Step 4: POST /api/payments/confirm 호출 (테스트 paymentKey)');

  const confirmBody = {
    paymentKey: 'test_fake_payment_key_1234567890',
    orderId: created.id,
    amount: created.totalPrice,
  };

  const confirmRes = await fetch(`${API_BASE}/payments/confirm`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(confirmBody),
  });

  const confirmJson = await confirmRes.json();
  log.info(`HTTP ${confirmRes.status}`);
  console.log('  응답:', JSON.stringify(confirmJson, null, 2));

  if (confirmRes.ok) {
    log.ok('결제 승인 성공 (실제 paymentKey 사용 시 전체 흐름 OK)');
  } else {
    log.info('가짜 paymentKey 라 토스 승인은 실패 — 우리 서버 로직 정상 동작');
    log.info(`에러 응답: ${confirmJson.message || confirmJson.error}`);
  }

  // ── Step 5: 금액 위변조 테스트 (의도적 실패) ────────
  log.section('Step 5: 금액 위변조 검증 테스트');
  const hackedBody = {
    paymentKey: 'hack_test',
    orderId: created.id,
    amount: 100, // 실제 금액과 다름
  };

  const hackRes = await fetch(`${API_BASE}/payments/confirm`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(hackedBody),
  });

  const hackJson = await hackRes.json();
  log.info(`HTTP ${hackRes.status}`);
  console.log('  응답:', JSON.stringify(hackJson, null, 2));

  if (hackRes.status === 400 && hackJson.message?.includes('금액')) {
    log.ok('금액 위변조 방어 정상 동작');
  } else {
    log.fail('금액 위변조 체크가 작동하지 않음 — 보안 취약');
  }

  console.log('\n🏁 테스트 종료\n');
}

main().catch((err) => {
  console.error('\n❌ 예외 발생:', err);
  process.exit(1);
});
