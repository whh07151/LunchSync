-- ══════════════════════════════════════════════════════════
-- 마이그레이션: users.favorites JSONB 컬럼 추가 (2026-05-15)
--
-- 배경 (자율 발전 — 배민 패턴 적용):
--   배달의민족·쿠팡이츠 핵심 기능 = 즐겨찾기 (자주 가는 식당).
--   팀 점심 매칭 LunchSync 에서도 "이 식당 또 갈래?" 빠른 재선택에 유용.
--
-- 데이터 모델:
--   - favorites JSONB DEFAULT '[]'::jsonb — 식당 UUID 배열
--   - 정렬 순서 = 추가 순 (가장 최근이 배열 마지막)
--   - 최대 100개 (소프트 한도 — 서비스 단에서 검증)
--
-- 안전성:
--   - IF NOT EXISTS — 재실행 안전
--   - DEFAULT '[]' — 기존 사용자도 영향 없음 (빈 배열)
--   - NULL 허용 안 함 (NOT NULL DEFAULT '[]')
--
-- 코드 동기화:
--   backend/src/users/users.service.ts 의 addFavorite/removeFavorite/listFavorites
--   메서드와 1:1 일치.
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS favorites JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 빠른 검색을 위한 GIN 인덱스 (JSONB 배열 안에 특정 식당 ID 있는지 검사)
CREATE INDEX IF NOT EXISTS idx_users_favorites_gin
  ON users USING GIN (favorites);

COMMENT ON COLUMN users.favorites
  IS '즐겨찾기 식당 ID 배열 (UUID 문자열). 추가 순 정렬';

COMMIT;

-- ── 검증 ─────────────────────────────────────────────────
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='users' AND column_name='favorites';
-- 기대: favorites / jsonb
