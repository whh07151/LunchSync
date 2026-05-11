/* eslint-disable @typescript-eslint/no-floating-promises */
import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';

// ══════════════════════════════════════════════════════════
// 파일 역할: 장다연 식당 + 메뉴 시드 데이터 DB 삽입 스크립트
//
// 용도:
//   Flutter의 restaurant_seeds.dart / menu_seeds.dart와
//   동일한 UUID를 사용하여 Supabase DB에 실제 레코드 삽입.
//   추천 → 투표 → 메뉴 → 주문 → 결제 흐름이 끊기지 않도록 함.
//
// 실행:
//   cd backend
//   npx ts-node scripts/seed-restaurants.ts
//
// 멱등성:
//   upsert 사용하므로 여러 번 실행해도 중복 에러 없음
// ══════════════════════════════════════════════════════════

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('❌ SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 가 .env 에 없습니다.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// ══════════════════════════════════════════════════════════
// UUID 규칙:
//   식당: rest_NNN → bbbbbbbb-0000-4000-8000-000000000NNN
//   메뉴: menu_NNN_MM → cccccccc-0NNN-4000-8000-0000000000MM
//
// 이 UUID는 Flutter의 restaurant_seeds.dart, menu_seeds.dart에서
// 동일하게 사용해야 프론트↔DB ID가 일치합니다.
// ══════════════════════════════════════════════════════════

const RESTAURANTS = [
  { id: 'bbbbbbbb-0000-4000-8000-000000000001', name: '한솥도시락',              category: '한식', price_range: 5500,  lat: 37.5665, lng: 126.9780, address: '서울시 중구 세종대로 110' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000002', name: '김밥천국',               category: '분식', price_range: 5000,  lat: 37.5670, lng: 126.9785, address: '서울시 중구 명동길 25' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000003', name: '스시로',                 category: '일식', price_range: 15000, lat: 37.5660, lng: 126.9770, address: '서울시 중구 을지로 50' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000004', name: '맘스터치',               category: '양식', price_range: 6500,  lat: 37.5668, lng: 126.9790, address: '서울시 중구 충무로 30' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000005', name: '순남시래기',             category: '한식', price_range: 9500,  lat: 37.5663, lng: 126.9775, address: '서울시 중구 남대문로 80' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000006', name: '홍콩반점',               category: '중식', price_range: 7500,  lat: 37.5672, lng: 126.9788, address: '서울시 중구 퇴계로 40' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000007', name: '서브웨이',               category: '양식', price_range: 7500,  lat: 37.5667, lng: 126.9782, address: '서울시 중구 세종대로 200' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000008', name: '이디야커피',             category: '카페', price_range: 4000,  lat: 37.5664, lng: 126.9778, address: '서울시 중구 명동길 10' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000009', name: '봉추찜닭',               category: '한식', price_range: 23000, lat: 37.5661, lng: 126.9772, address: '서울시 중구 을지로 100' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000010', name: '역전우동',               category: '일식', price_range: 6750,  lat: 37.5669, lng: 126.9786, address: '서울시 중구 충무로 60' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000011', name: '백소정',                 category: '일식', price_range: 10500, lat: 37.5658, lng: 126.9768, address: '서울시 중구 퇴계로 90' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000012', name: '본죽',                   category: '한식', price_range: 8500,  lat: 37.5666, lng: 126.9781, address: '서울시 중구 남대문로 120' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000013', name: '교촌치킨',               category: '양식', price_range: 17000, lat: 37.5673, lng: 126.9792, address: '서울시 중구 명동길 55' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000014', name: '하남돼지집',             category: '한식', price_range: 14000, lat: 37.5655, lng: 126.9765, address: '서울시 중구 을지로 150' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000015', name: '쌈밥집',                 category: '한식', price_range: 9000,  lat: 37.5671, lng: 126.9787, address: '서울시 중구 충무로 45' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000016', name: '신전떡볶이',             category: '분식', price_range: 4500,  lat: 37.5674, lng: 126.9793, address: '서울시 중구 퇴계로 20' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000017', name: '아웃백 스테이크하우스',   category: '양식', price_range: 25000, lat: 37.5652, lng: 126.9760, address: '서울시 중구 세종대로 300' },
  { id: 'bbbbbbbb-0000-4000-8000-000000000018', name: 'CoCo 이찌방야',         category: '일식', price_range: 9500,  lat: 37.5668, lng: 126.9783, address: '서울시 중구 명동길 70' },
];

const MENU_ITEMS = [
  // rest_001: 한솥도시락
  { id: 'cccccccc-0001-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000001', name: '치킨마요도시락',    price: 5500,  category: 'rice',   description: '바삭한 치킨에 고소한 마요네즈를 얹은 인기 도시락' },
  { id: 'cccccccc-0001-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000001', name: '제육도시락',        price: 6000,  category: 'rice',   description: '매콤달콤 제육볶음이 듬뿍 들어간 도시락' },
  { id: 'cccccccc-0001-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000001', name: '참치김치도시락',    price: 5000,  category: 'rice',   description: '고소한 참치와 볶음김치의 조합' },

  // rest_002: 김밥천국
  { id: 'cccccccc-0002-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000002', name: '참치김밥',          price: 4000,  category: 'snack',  description: '고소한 참치마요가 가득한 김밥' },
  { id: 'cccccccc-0002-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000002', name: '떡볶이',            price: 4500,  category: 'snack',  description: '매콤한 고추장 소스의 국민 분식' },
  { id: 'cccccccc-0002-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000002', name: '라볶이',            price: 5500,  category: 'noodle', description: '떡볶이에 라면 사리를 추가한 조합' },

  // rest_003: 스시로
  { id: 'cccccccc-0003-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000003', name: '연어초밥세트',      price: 15000, category: 'rice',   description: '신선한 연어 8피스 초밥 세트' },
  { id: 'cccccccc-0003-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000003', name: '참치회덮밥',        price: 13000, category: 'rice',   description: '참치회를 듬뿍 올린 덮밥' },
  { id: 'cccccccc-0003-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000003', name: '새우튀김우동',      price: 12000, category: 'noodle', description: '바삭한 새우튀김과 진한 다시 육수 우동' },

  // rest_004: 맘스터치
  { id: 'cccccccc-0004-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000004', name: '싸이버거',          price: 5200,  category: 'rice',   description: '두툼한 닭다리살 패티의 시그니처 버거' },
  { id: 'cccccccc-0004-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000004', name: '불싸이버거',        price: 5700,  category: 'rice',   description: '매콤한 소스를 더한 싸이버거' },
  { id: 'cccccccc-0004-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000004', name: '케이준 감자',       price: 2500,  category: 'snack',  description: '바삭한 감자에 케이준 시즈닝을 뿌린 사이드' },

  // rest_005: 순남시래기
  { id: 'cccccccc-0005-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000005', name: '시래기된장찌개',    price: 9000,  category: 'rice',   description: '구수한 된장에 시래기를 넣어 끓인 찌개' },
  { id: 'cccccccc-0005-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000005', name: '시래기불고기',      price: 10000, category: 'rice',   description: '달콤한 불고기와 시래기의 건강한 조합' },
  { id: 'cccccccc-0005-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000005', name: '청국장찌개',        price: 9000,  category: 'rice',   description: '구수한 향이 진한 전통 청국장에 두부와 야채를 듬뿍' },

  // rest_006: 홍콩반점
  { id: 'cccccccc-0006-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000006', name: '짬뽕',              price: 7000,  category: 'noodle', description: '얼큰한 해물 국물의 대표 짬뽕' },
  { id: 'cccccccc-0006-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000006', name: '짜장면',            price: 6000,  category: 'noodle', description: '달달한 춘장 소스의 클래식 짜장면' },
  { id: 'cccccccc-0006-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000006', name: '탕수육(소)',        price: 13000, category: 'rice',   description: '바삭한 튀김옷에 새콤달콤 소스를 곁들인 탕수육' },

  // rest_007: 서브웨이
  { id: 'cccccccc-0007-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000007', name: '이탈리안 BMT',     price: 7400,  category: 'rice',   description: '페퍼로니, 살라미, 햄이 들어간 클래식 서브' },
  { id: 'cccccccc-0007-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000007', name: '에그마요',          price: 6500,  category: 'rice',   description: '고소한 에그마요네즈 샌드위치' },
  { id: 'cccccccc-0007-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000007', name: '로티세리 치킨',    price: 7900,  category: 'rice',   description: '부드러운 통닭 가슴살이 들어간 담백한 샌드위치' },

  // rest_008: 이디야커피
  { id: 'cccccccc-0008-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000008', name: '아메리카노',        price: 3300,  category: 'drink',  description: '깔끔한 에스프레소 기반 커피' },
  { id: 'cccccccc-0008-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000008', name: '카페라떼',          price: 4000,  category: 'drink',  description: '부드러운 우유와 에스프레소의 조화' },
  { id: 'cccccccc-0008-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000008', name: '크로플',            price: 4500,  category: 'drink',  description: '바삭한 크루아상 와플에 아이스크림을 곁들인 디저트' },

  // rest_009: 봉추찜닭
  { id: 'cccccccc-0009-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000009', name: '오리지널찜닭',      price: 22000, category: 'rice',   description: '간장 베이스 매콤달콤 찜닭 (2~3인분)' },
  { id: 'cccccccc-0009-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000009', name: '치즈찜닭',          price: 24000, category: 'rice',   description: '모짜렐라 치즈를 듬뿍 올린 찜닭' },
  { id: 'cccccccc-0009-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000009', name: '간장찜닭',          price: 22000, category: 'rice',   description: '안 매운 간장 베이스 찜닭 (2~3인분)' },

  // rest_010: 역전우동
  { id: 'cccccccc-0010-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000010', name: '가케우동',          price: 6500,  category: 'noodle', description: '진한 가쓰오부시 육수의 따뜻한 우동' },
  { id: 'cccccccc-0010-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000010', name: '냉우동',            price: 7000,  category: 'noodle', description: '시원한 냉육수에 쫄깃한 면발' },
  { id: 'cccccccc-0010-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000010', name: '카레우동',          price: 7500,  category: 'noodle', description: '진한 일본식 카레 소스에 쫄깃한 우동 면' },

  // rest_011: 백소정
  { id: 'cccccccc-0011-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000011', name: '돈코츠라멘',        price: 10000, category: 'noodle', description: '18시간 우려낸 진한 돼지뼈 육수 라멘' },
  { id: 'cccccccc-0011-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000011', name: '매운라멘',          price: 11000, category: 'noodle', description: '돈코츠 베이스에 매운 소스를 추가한 라멘' },
  { id: 'cccccccc-0011-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000011', name: '차슈덮밥',          price: 9500,  category: 'rice',   description: '부드러운 차슈를 올린 일본식 덮밥' },

  // rest_012: 본죽
  { id: 'cccccccc-0012-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000012', name: '전복죽',            price: 10000, category: 'rice',   description: '통전복이 들어간 영양 가득 죽' },
  { id: 'cccccccc-0012-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000012', name: '소고기야채죽',      price: 8000,  category: 'rice',   description: '소고기와 야채를 넣어 끓인 담백한 죽' },
  { id: 'cccccccc-0012-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000012', name: '참치야채죽',        price: 7500,  category: 'rice',   description: '고소한 참치와 야채의 부드러운 조합' },

  // rest_013: 교촌치킨
  { id: 'cccccccc-0013-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000013', name: '교촌오리지널',      price: 18000, category: 'rice',   description: '바삭한 튀김옷에 달콤한 간장 소스를 입힌 시그니처 치킨' },
  { id: 'cccccccc-0013-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000013', name: '레드콤보',          price: 16000, category: 'rice',   description: '매콤한 레드 소스의 순살 치킨 + 감자 세트' },
  { id: 'cccccccc-0013-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000013', name: '허니콤보',          price: 17000, category: 'rice',   description: '달콤한 허니 소스를 입힌 순살 치킨' },

  // rest_014: 하남돼지집
  { id: 'cccccccc-0014-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000014', name: '삼겹살 (1인분)',    price: 14000, category: 'rice',   description: '두툼하게 썬 국내산 삼겹살을 숯불에 구워 먹는 메뉴' },
  { id: 'cccccccc-0014-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000014', name: '목살 (1인분)',      price: 13000, category: 'rice',   description: '부드러운 결이 살아있는 목살구이' },
  { id: 'cccccccc-0014-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000014', name: '된장찌개',          price: 3000,  category: 'rice',   description: '고기와 함께 먹기 좋은 구수한 된장찌개' },

  // rest_015: 쌈밥집
  { id: 'cccccccc-0015-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000015', name: '쌈밥정식',          price: 9000,  category: 'rice',   description: '신선한 쌈 채소 10종과 쌈장, 밥, 국이 함께 나오는 정식' },
  { id: 'cccccccc-0015-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000015', name: '제육쌈밥',          price: 10000, category: 'rice',   description: '매콤한 제육볶음을 쌈에 싸서 먹는 보양 한 끼' },
  { id: 'cccccccc-0015-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000015', name: '두부된장쌈밥',      price: 8500,  category: 'rice',   description: '두부와 된장을 곁들인 담백한 채소 쌈밥' },

  // rest_016: 신전떡볶이
  { id: 'cccccccc-0016-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000016', name: '신전떡볶이',        price: 4500,  category: 'snack',  description: '즉석에서 볶아내는 매콤달콤 떡볶이' },
  { id: 'cccccccc-0016-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000016', name: '순대',              price: 4000,  category: 'snack',  description: '당면이 가득 찬 쫄깃한 찹쌀순대' },
  { id: 'cccccccc-0016-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000016', name: '모듬튀김',          price: 5000,  category: 'snack',  description: '고구마·김말이·오징어 등 바삭한 모듬튀김' },

  // rest_017: 아웃백 스테이크하우스
  { id: 'cccccccc-0017-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000017', name: '토마호크 스테이크', price: 49000, category: 'rice',   description: '육즙 가득한 대형 토마호크 스테이크 (2인 이상)' },
  { id: 'cccccccc-0017-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000017', name: '투움바 파스타',     price: 18000, category: 'noodle', description: '크리미한 투움바 소스에 새우와 베이컨을 올린 파스타' },
  { id: 'cccccccc-0017-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000017', name: '런치 스테이크 세트', price: 22000, category: 'rice',  description: '부드러운 안심 스테이크에 수프·샐러드가 포함된 런치 세트' },

  // rest_018: CoCo 이찌방야
  { id: 'cccccccc-0018-4000-8000-000000000001', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000018', name: '비프카레',          price: 9500,  category: 'rice',   description: '부드러운 소고기 덩어리가 들어간 진한 일본식 카레' },
  { id: 'cccccccc-0018-4000-8000-000000000002', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000018', name: '치킨카츠카레',      price: 10500, category: 'rice',   description: '바삭한 치킨카츠를 올린 카레라이스' },
  { id: 'cccccccc-0018-4000-8000-000000000003', restaurant_id: 'bbbbbbbb-0000-4000-8000-000000000018', name: '야채카레',          price: 8500,  category: 'rice',   description: '감자·당근·브로콜리 등 야채가 듬뿍 들어간 순한 카레' },
];

// ── 메인 ────────────────────────────────────────────────
async function main() {
  console.log('🌱 장다연 식당+메뉴 시드 시작\n');

  // 1) 식당 18곳 upsert
  console.log('🍚 restaurants upsert (18곳)...');
  const { error: restErr } = await supabase
    .from('restaurants')
    .upsert(RESTAURANTS);

  if (restErr) {
    console.error('❌ restaurants 실패:', restErr.message);
    process.exit(1);
  }
  console.log(`   ✓ ${RESTAURANTS.length}곳 완료`);

  // 2) 메뉴 54건 upsert
  console.log('\n🍱 menu_items upsert (54건)...');
  const { error: menuErr } = await supabase
    .from('menu_items')
    .upsert(MENU_ITEMS);

  if (menuErr) {
    console.error('❌ menu_items 실패:', menuErr.message);
    process.exit(1);
  }
  console.log(`   ✓ ${MENU_ITEMS.length}건 완료`);

  console.log('\n✅ 시드 완료!\n');
  console.log('UUID 규칙:');
  console.log('  식당: bbbbbbbb-0000-4000-8000-000000000NNN');
  console.log('  메뉴: cccccccc-0NNN-4000-8000-0000000000MM');
  console.log('\nFlutter seed 파일의 ID도 동일하게 맞춰야 합니다.');
}

main().catch((err) => {
  console.error('❌ 예외:', err);
  process.exit(1);
});
