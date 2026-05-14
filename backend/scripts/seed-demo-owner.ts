/* eslint-disable @typescript-eslint/no-floating-promises */
import { createClient } from '@supabase/supabase-js';
import * as bcrypt from 'bcrypt';
import * as dotenv from 'dotenv';
import * as path from 'path';

// ══════════════════════════════════════════════════════════
// 파일 역할: Playwright 시연 영상용 사장(OWNER) 시드 계정 생성
//
// 용도:
//   pos-demo-recording.spec.ts 가 사용할 사장 계정을 idempotent 하게 생성.
//   - 이미 있으면 status='APPROVED' + restaurant_id 만 보정
//   - 없으면 INSERT (bcrypt 해시 비번 + role='OWNER' + status='APPROVED')
//
// 매핑되는 식당:
//   2026-05-12-seed-demo-data.sql 의 첫 번째 식당
//   '11111111-1111-1111-1111-111111111111' (강남 김밥천국)
//
// 시연 계정:
//   email    : demo.owner@lunchsync.test
//   password : DemoOwner1!
//
// 실행:
//   cd backend && npx ts-node scripts/seed-demo-owner.ts
// ══════════════════════════════════════════════════════════

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('❌ SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 누락');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// 시연용 고정 상수
const DEMO_EMAIL = 'demo.owner@lunchsync.test';
const DEMO_PASSWORD = 'DemoOwner1!';
const DEMO_NAME = '시연 사장';
const DEMO_RESTAURANT_ID = '11111111-1111-1111-1111-111111111111';

async function main() {
  console.log('🌱 시연용 OWNER 시드 시작');

  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 10);

  // 1) 기존 계정 조회
  const { data: existing } = await supabase
    .from('users')
    .select('id, email')
    .eq('email', DEMO_EMAIL)
    .maybeSingle();

  if (existing) {
    console.log(`👤 기존 계정 갱신: ${existing.id}`);
    const { error: upErr } = await supabase
      .from('users')
      .update({
        password_hash: passwordHash,
        role: 'OWNER',
        status: 'APPROVED',
        restaurant_id: DEMO_RESTAURANT_ID,
        name: DEMO_NAME,
      })
      .eq('id', existing.id);
    if (upErr) {
      console.error('❌ update 실패:', upErr.message);
      process.exit(1);
    }
    console.log('   ✓ password/role/status/restaurant_id 갱신 완료');
  } else {
    console.log('👤 신규 OWNER INSERT');
    const { data: inserted, error: insErr } = await supabase
      .from('users')
      .insert({
        email: DEMO_EMAIL,
        name: DEMO_NAME,
        password_hash: passwordHash,
        role: 'OWNER',
        status: 'APPROVED',
        restaurant_id: DEMO_RESTAURANT_ID,
        auth_provider: 'EMAIL',
        // kakao_id 가 NOT NULL 인 레거시 스키마 대응 — 시연용 더미값
        kakao_id: 'demo_owner_seed_' + Date.now(),
      })
      .select('id')
      .single();
    if (insErr) {
      console.error('❌ insert 실패:', insErr.message);
      process.exit(1);
    }
    console.log(`   ✓ ${inserted.id}`);
  }

  console.log('\n✅ 시연 계정 준비 완료');
  console.log(`   email    : ${DEMO_EMAIL}`);
  console.log(`   password : ${DEMO_PASSWORD}`);
  console.log(`   restaurant_id : ${DEMO_RESTAURANT_ID}`);
}

main().catch((e) => {
  console.error('❌ 예외:', e);
  process.exit(1);
});
