-- ══════════════════════════════════════════════════════════
-- 마이그레이션: tournament_results 테이블 (2026-05-31, WOW#9)
--
-- 목적:
--   WOW#6 토너먼트(식당/메뉴 이상형월드컵)의 우승 결과를 영구 저장.
--   누적된 우승 데이터를 GROUP BY winner_restaurant_id 집계하면
--   "이번 주 토너먼트 인기 식당" 트렌딩 섹션(WOW#9)을 만들 수 있다.
--
-- 흐름:
--   1) Flutter tournament_screen 에서 우승 화면 진입 시
--      → POST /api/tournaments 백그라운드 호출(실패해도 UX 막지 않음)
--   2) 백엔드 tournaments.service 가 본 테이블에 1행 INSERT
--   3) 홈 화면이 GET /api/tournaments/trending?limit=5&days=7 조회
--      → 최근 N일 동안 winner_restaurant_id GROUP BY count desc
--      → 가로 스크롤 카드 5개로 노출 (데이터 0개면 섹션 숨김)
--
-- 컬럼:
--   id                     UUID PK (기본 gen_random_uuid())
--   user_id                UUID FK(users.id) — 누가 우승 결정했는지 (분석용)
--   mode                   TEXT — 'restaurant' | 'menu' (CHECK 제약)
--   winner_restaurant_id   UUID FK(restaurants.id) — 식당 모드 또는 메뉴 모드의 소속 식당
--   winner_menu_id         UUID FK(menus.id) — 메뉴 모드일 때만 채움
--   candidate_count        INT — 시작 후보 수(8/4/6 등) — 토너먼트 규모 분석용
--   duration_ms            INT — 진입~우승까지 소요 시간(ms) — 사용자 결정력 분석용
--   created_at             TIMESTAMPTZ DEFAULT NOW()
--
-- 안전성 (멱등):
--   - CREATE TABLE IF NOT EXISTS — 이미 있으면 no-op
--   - CREATE INDEX IF NOT EXISTS — 인덱스 중복 생성 방지
--   - FK ON DELETE 정책은 명시 안 함 → PostgreSQL 기본(NO ACTION)
--     · users/restaurants/menus 가 삭제되면 INSERT 차단 → 데이터 무결성 유지
--
-- 인덱스:
--   - idx_tournament_results_created            : 최근 N일 필터 (트렌딩 조회 핵심)
--   - idx_tournament_results_winner_restaurant  : GROUP BY winner_restaurant_id
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → 전체 붙여넣기 → Run.
--   적용 후 verify-schema.sql 의 테이블 검증 쿼리에서 tournament_results 확인.
--
-- 검증 쿼리 (실행 후 결과 확인):
--   SELECT column_name, data_type FROM information_schema.columns
--     WHERE table_name='tournament_results' ORDER BY ordinal_position;
--   SELECT indexname FROM pg_indexes WHERE tablename='tournament_results';
-- ══════════════════════════════════════════════════════════

-- ── 1) 본체 테이블 ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tournament_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  mode TEXT NOT NULL CHECK (mode IN ('restaurant', 'menu')),
  winner_restaurant_id UUID REFERENCES restaurants(id),
  -- 2026-05-31 fix: menus 가 아니라 menu_items 가 실제 테이블명 (CORE-09 동일 이슈)
  winner_menu_id UUID REFERENCES menu_items(id),
  candidate_count INT,
  duration_ms INT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE tournament_results IS
  'WOW#6 토너먼트 우승 결과 로그 — WOW#9 주간 트렌딩 식당 집계 소스';

COMMENT ON COLUMN tournament_results.mode IS
  '토너먼트 모드 — restaurant(식당) | menu(메뉴). CHECK 제약으로 다른 값 차단.';

COMMENT ON COLUMN tournament_results.winner_restaurant_id IS
  '우승 식당 ID. 식당 모드면 항상 채워지고, 메뉴 모드면 그 메뉴의 소속 식당이 채워짐. '
  '둘 다 NULL 인 케이스는 비정상 — 백엔드 service 에서 차단.';

COMMENT ON COLUMN tournament_results.winner_menu_id IS
  '우승 메뉴 ID. 메뉴 모드일 때만 채워짐. 식당 모드는 NULL.';

COMMENT ON COLUMN tournament_results.candidate_count IS
  '시작 후보 수(보통 2/4/6/8). 후보 부족으로 4강·결승 직행한 경우도 그대로 기록.';

COMMENT ON COLUMN tournament_results.duration_ms IS
  '진입(모드 선택 직후 첫 페어 표시)부터 우승 화면 진입까지의 누적 ms. '
  '0 또는 음수 NULL 허용 — 클라이언트 단의 시계 분단(rebuild) 가 클 수 있어 분석용 보조 지표.';

-- ── 2) 인덱스 ─────────────────────────────────────────────
-- 트렌딩 쿼리: WHERE created_at >= now() - interval 'N days'
--             GROUP BY winner_restaurant_id ORDER BY count desc
-- 위 두 절에 가장 빈번하게 사용되므로 created_at desc + winner_restaurant_id 단일 인덱스.

CREATE INDEX IF NOT EXISTS idx_tournament_results_created
  ON tournament_results (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_tournament_results_winner_restaurant
  ON tournament_results (winner_restaurant_id);

-- ── 3) (옵션) 적용 검증 ──────────────────────────────────
-- 실행 후 아래 두 쿼리가 비어있지 않으면 정상.
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='tournament_results' ORDER BY ordinal_position;
-- SELECT indexname FROM pg_indexes WHERE tablename='tournament_results';
