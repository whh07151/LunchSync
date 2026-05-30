/* eslint-disable @typescript-eslint/no-floating-promises */
import { createClient } from '@supabase/supabase-js';
import * as bcrypt from 'bcrypt';
import * as dotenv from 'dotenv';
import * as path from 'path';

// ══════════════════════════════════════════════════════════
// 파일 역할: Playwright 3분할 시연 영상용 손님(CUSTOMER) 시드 계정 생성
//
// 용도:
//   triplet-demo-recording.spec.ts 가 사용할 손님 계정을 idempotent 하게 생성.
//   - 이미 있으면 status='APPROVED' + password 만 보정
//   - 없으면 INSERT (bcrypt 해시 비번 + role='CUSTOMER' + status='APPROVED')
//
// 왜 만드는가:
//   기존 시드 친구 5명(demo.minjun 등)은 비밀번호가 없어서 카카오 로그인 전용.
//   Playwright 에서는 카카오 OAuth 자동화가 불가 → 이메일+비밀번호 로그인 가능한
//   별도 손님 계정이 필요. seed-demo-owner.ts 와 동일한 패턴.
//
// 시연 계정:
//   email    : demo.customer@lunchsync.test
//   password : DemoCust1!
//
// 실행:
//   cd backend && npx ts-node scripts/seed-demo-customer.ts
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
const DEMO_EMAIL = 'demo.customer@lunchsync.test';
const DEMO_PASSWORD = 'DemoCust1!';
const DEMO_NAME = '시연 손님';

async function main() {
  console.log('🌱 시연용 CUSTOMER 시드 시작');

  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 10);

  // 1) 기존 계정 조회
  const { data: existing } = await supabase
    .from('users')
    .select('id, email')
    .eq('email', DEMO_EMAIL)
    .maybeSingle();

  // _resolveAutoLoginNextStep 이 org/budget/speed 가 비면 PROFILE_SETUP/CONDITION_SETUP
  // 으로 보내므로 시연용은 모두 채워서 HOME 으로 바로 진입하도록 강제.
  const onboardingDefaults = {
    org: '시연팀',
    budget: 10000,
    speed: 'normal',
    radius: 500,
  };

  if (existing) {
    console.log(`👤 기존 계정 갱신: ${existing.id}`);
    const { error: upErr } = await supabase
      .from('users')
      .update({
        password_hash: passwordHash,
        role: 'CUSTOMER',
        status: 'APPROVED',
        name: DEMO_NAME,
        ...onboardingDefaults,
      })
      .eq('id', existing.id);
    if (upErr) {
      console.error('❌ update 실패:', upErr.message);
      process.exit(1);
    }
    console.log('   ✓ password/role/status + 온보딩 기본값 갱신 완료');
  } else {
    console.log('👤 신규 CUSTOMER INSERT');
    const { data: inserted, error: insErr } = await supabase
      .from('users')
      .insert({
        email: DEMO_EMAIL,
        name: DEMO_NAME,
        password_hash: passwordHash,
        role: 'CUSTOMER',
        status: 'APPROVED',
        auth_provider: 'EMAIL',
        // kakao_id 가 NOT NULL 인 레거시 스키마 대응 — 시연용 더미값
        kakao_id: 'demo_customer_seed_' + Date.now(),
        ...onboardingDefaults,
      })
      .select('id')
      .single();
    if (insErr) {
      console.error('❌ insert 실패:', insErr.message);
      process.exit(1);
    }
    console.log(`   ✓ ${inserted.id}`);
  }

  console.log('\n✅ 시연 손님 계정 준비 완료');
  console.log(`   email    : ${DEMO_EMAIL}`);
  console.log(`   password : ${DEMO_PASSWORD}`);
}

main().catch((e) => {
  console.error('❌ 예외:', e);
  process.exit(1);
});
