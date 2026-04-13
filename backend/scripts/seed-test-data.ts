/* eslint-disable @typescript-eslint/no-floating-promises */
import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';

// ══════════════════════════════════════════════════════════
// 파일 역할: LunchSync 테스트 데이터 시드 스크립트
//
// 용도:
//   Flutter 의 menu_screen.dart / order_review_screen.dart 가
//   사용하는 mock ID 들을 Supabase DB 에 실제 레코드로 삽입.
//   주문/결제 흐름 end-to-end 테스트를 가능하게 함.
//
// 실행:
//   cd backend
//   npx ts-node scripts/seed-test-data.ts
//
// 삽입되는 데이터:
//   - restaurants 1건 (테스트 한식집)
//   - menu_items 12건 (Flutter _mockMenuItems 와 1:1 매칭)
//   - sessions 1건 (WAITING 상태)
//   - session_members 1건 (로그인한 테스트 유저 = 방장)
//
// 고정 UUID (Flutter 에 하드코딩한 값과 동일):
//   restaurantId : 11111111-1111-1111-1111-111111111111
//   sessionId    : 22222222-2222-2222-2222-222222222222
//   menuItemIds  : aaaaaaaa-0000-4000-8000-000000000001 ~ 000000000012
//
// 멱등성:
//   upsert 를 사용하므로 여러 번 실행해도 중복 에러 없음
// ══════════════════════════════════════════════════════════

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('❌ SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 가 .env 에 없습니다.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// ── 고정 UUID 상수 ─────────────────────────────────────
const RESTAURANT_ID = '11111111-1111-1111-1111-111111111111';
const SESSION_ID = '22222222-2222-2222-2222-222222222222';

// Flutter menu_screen.dart 의 mock 메뉴 12개와 1:1 대응
// id 마지막 숫자가 m01~m12 의 번호와 맞음
const MENU_ITEMS = [
  { id: 'aaaaaaaa-0000-4000-8000-000000000001', name: '불고기 덮밥',        price: 8900, category: 'rice',        description: '달콤한 불고기 소스와 부드러운 소고기가 밥 위에 올려진 메뉴' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000002', name: '치즈 돈까스',        price: 9500, category: 'rice',        description: '두툼한 돼지고기 커틀릿에 진한 치즈 소스' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000003', name: '제육볶음 정식',      price: 9000, category: 'rice',        description: '매콤한 제육볶음 + 공깃밥 + 국 + 반찬 3종' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000004', name: '김치찌개 정식',      price: 8500, category: 'rice',        description: '묵은지로 끓인 진한 김치찌개 + 밥 + 반찬' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000005', name: '비빔밥',             price: 8000, category: 'rice',        description: '신선한 야채와 고추장으로 비벼 먹는 건강 한 끼' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000006', name: '잔치국수',           price: 7000, category: 'noodle',      description: '멸치 육수에 소면을 넣은 담백한 국수' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000007', name: '비빔국수',           price: 7500, category: 'noodle',      description: '새콤달콤한 양념장에 비벼 먹는 여름 별미' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000008', name: '떡볶이',             price: 6000, category: 'snack',       description: '쫄깃한 가래떡에 매콤달콤한 소스. 순한맛/매운맛 선택' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000009', name: '김밥 (1줄)',         price: 4000, category: 'snack',       description: '참기름 향 가득한 참치김밥. 야채·참치·계란 구성' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000010', name: '순대볶음',           price: 8000, category: 'snack',       description: '당면이 가득한 순대를 매콤하게 볶은 메뉴' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000011', name: '아이스 아메리카노',  price: 2500, category: 'drink',       description: '깔끔한 에스프레소에 얼음을 가득 넣은 아이스 커피' },
  { id: 'aaaaaaaa-0000-4000-8000-000000000012', name: '식혜',               price: 2000, category: 'drink',       description: '전통 발효 음료. 달달하고 시원한 맛' },
];

// ── 메인 ────────────────────────────────────────────────
async function main() {
  console.log('🌱 LunchSync 테스트 데이터 시드 시작\n');

  // 1) 방장(테스트 유저) 탐색: 현재 DB 에 있는 첫 번째 유저 사용
  // (우현호 = 9b60f82f-159f-4400-9660-0a4bc595af77 로그에서 확인된 값)
  const { data: users, error: userErr } = await supabase
    .from('users')
    .select('id, name')
    .limit(5);

  if (userErr || !users || users.length === 0) {
    console.error('❌ users 테이블에 유저가 없습니다. 먼저 카카오 로그인으로 유저 1명 이상 생성해주세요.');
    process.exit(1);
  }

  const hostUser = users[0];
  console.log(`👤 방장 유저: ${hostUser.name} (${hostUser.id})`);
  console.log(`   (users 테이블 전체 ${users.length}명 중 첫 번째 사용)\n`);

  // 2) 식당 upsert
  console.log('🍚 restaurants upsert...');
  const { error: restaurantErr } = await supabase
    .from('restaurants')
    .upsert({
      id: RESTAURANT_ID,
      name: '테스트 한식집',
      category: '한식',
      price_range: 2,
      lat: 37.5665,
      lng: 126.9780,
      address: '서울특별시 중구 세종대로 110 (테스트용)',
    });
  if (restaurantErr) {
    console.error('❌ restaurants 실패:', restaurantErr.message);
    process.exit(1);
  }
  console.log(`   ✓ ${RESTAURANT_ID}`);

  // 3) menu_items upsert (12건 일괄)
  console.log('\n🍱 menu_items upsert (12건)...');
  const menuRows = MENU_ITEMS.map((m) => ({
    id: m.id,
    restaurant_id: RESTAURANT_ID,
    name: m.name,
    price: m.price,
    category: m.category,
    description: m.description,
  }));

  const { error: menuErr } = await supabase.from('menu_items').upsert(menuRows);
  if (menuErr) {
    console.error('❌ menu_items 실패:', menuErr.message);
    process.exit(1);
  }
  console.log(`   ✓ ${menuRows.length}건 완료`);

  // 4) session upsert
  console.log('\n🍽️ sessions upsert...');
  const { error: sessionErr } = await supabase
    .from('sessions')
    .upsert({
      id: SESSION_ID,
      name: '테스트 점심 세션',
      status: 'WAITING',
      created_by: hostUser.id,
    });
  if (sessionErr) {
    console.error('❌ sessions 실패:', sessionErr.message);
    process.exit(1);
  }
  console.log(`   ✓ ${SESSION_ID}`);

  // 5) session_members upsert (방장 자동 등록)
  console.log('\n👥 session_members upsert (방장)...');
  const { error: memberErr } = await supabase
    .from('session_members')
    .upsert(
      {
        session_id: SESSION_ID,
        user_id: hostUser.id,
      },
      { onConflict: 'session_id,user_id' },
    );
  if (memberErr) {
    console.error('❌ session_members 실패:', memberErr.message);
    process.exit(1);
  }
  console.log(`   ✓ ${hostUser.name} → 세션 멤버 등록`);

  console.log('\n✅ 시드 완료!\n');
  console.log('Flutter 에서 사용할 값:');
  console.log(`  sessionId    : ${SESSION_ID}`);
  console.log(`  restaurantId : ${RESTAURANT_ID}`);
  console.log(`  menuItemIds  : ${MENU_ITEMS[0].id} ~ ${MENU_ITEMS[11].id}`);
}

main().catch((err) => {
  console.error('❌ 예외:', err);
  process.exit(1);
});
