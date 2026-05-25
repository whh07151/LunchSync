-- 식당에 사장 계정 연결 컬럼 추가
-- Supabase SQL Editor 에서 실행하거나 psql 로 직접 실행

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_restaurants_owner_user_id
  ON restaurants(owner_user_id);