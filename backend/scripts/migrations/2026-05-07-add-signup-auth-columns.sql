-- ══════════════════════════════════════════════════════════
-- 파일 역할: 회원가입·인증·역할분리 결정(2026-05-07)에 따른 users 테이블 확장
--
-- 추가 컬럼:
--   1. status            — OWNER 가입 승인 상태 (PENDING/APPROVED/REJECTED)
--   2. auth_provider     — 가입 경로 (KAKAO/EMAIL/PHONE)
--   3. email             — 이메일 가입자의 로그인 ID
--   4. password_hash     — bcrypt 해시 (이메일 가입자만)
--   5. phone_number      — E.164 형식 (+8210...)
--   6. email_verified_at — 이메일 OTP 검증 완료 시각
--   7. phone_verified_at — Firebase Phone Auth 검증 완료 시각
--   8. business_name     — OWNER 가입 시 가게 상호명
--   9. business_number   — OWNER 가입 시 사업자등록번호
--
-- 적용 방법:
--   Supabase Dashboard → SQL Editor → 이 파일 내용 붙여넣기 → Run
--   또는 supabase CLI: supabase db push
--
-- 안전성:
--   ALTER TABLE ... ADD COLUMN IF NOT EXISTS — 이미 컬럼이 있어도 실패하지 않음
--   기본값 + NOT NULL — 기존 행에도 안전하게 적용됨
-- ══════════════════════════════════════════════════════════

-- ── ENUM 타입 정의 ──────────────────────────────────────
-- 이미 존재하면 무시 (CREATE TYPE에는 IF NOT EXISTS가 없어 DO 블록 사용)
DO $$ BEGIN
  CREATE TYPE user_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE auth_provider_type AS ENUM ('KAKAO', 'EMAIL', 'PHONE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── users 테이블 컬럼 추가 ───────────────────────────────
-- 기본값 APPROVED: 기존 카카오 가입자는 모두 활성 상태로 유지
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS status            user_status        NOT NULL DEFAULT 'APPROVED',
  ADD COLUMN IF NOT EXISTS auth_provider     auth_provider_type NOT NULL DEFAULT 'KAKAO',
  ADD COLUMN IF NOT EXISTS email             TEXT,
  ADD COLUMN IF NOT EXISTS password_hash     TEXT,
  ADD COLUMN IF NOT EXISTS phone_number      TEXT,
  ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS business_name     TEXT,
  ADD COLUMN IF NOT EXISTS business_number   TEXT;

-- ── 유니크 제약 ─────────────────────────────────────────
-- 같은 이메일로 중복 가입 방지 (NULL은 허용 — 카카오 가입자는 email NULL 가능)
DO $$ BEGIN
  CREATE UNIQUE INDEX users_email_unique_idx
    ON users(email)
    WHERE email IS NOT NULL;
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- 사업자등록번호 중복 방지 (한 사업자 = 한 OWNER 계정)
DO $$ BEGIN
  CREATE UNIQUE INDEX users_business_number_unique_idx
    ON users(business_number)
    WHERE business_number IS NOT NULL;
EXCEPTION WHEN duplicate_table THEN NULL;
END $$;

-- ── 조회 성능용 인덱스 ──────────────────────────────────
-- OWNER 승인 대기 목록 조회 시 (운영자가 콘솔에서 자주 사용)
CREATE INDEX IF NOT EXISTS users_role_status_idx
  ON users(role, status);

-- 이메일 로그인 시 빠른 조회
CREATE INDEX IF NOT EXISTS users_email_idx
  ON users(email);
