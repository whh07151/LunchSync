-- ══════════════════════════════════════════════════════════
-- 파일 역할: users.status 컬럼을 varchar → user_status ENUM으로 전환
--
-- 배경:
--   2026-05-07 마이그레이션(2026-05-07-add-signup-auth-columns.sql)에서
--   `status user_status` 컬럼을 추가하려 했으나, ADD COLUMN IF NOT EXISTS 가
--   이미 존재하던 varchar 타입 status 컬럼(default 'ACTIVE')을 그대로 두고 통과.
--   결과: 코드는 ENUM('PENDING'/'APPROVED'/'REJECTED')을 가정하나
--         DB는 varchar('ACTIVE') 상태로 명세와 어긋남.
--
-- 진단 (2026-05-11, Supabase SQL Editor 검증):
--   - status: data_type=character varying, udt_name=varchar,
--             default='ACTIVE'::character varying, nullable=YES
--   - auth_provider: 정상 (USER-DEFINED, auth_provider_type, default='KAKAO')
--   - 기존 행 분포: ACTIVE/KAKAO 5건만 존재 → 모두 'APPROVED'로 매핑 가능
--
-- 적용 방법:
--   Supabase Dashboard → SQL Editor → 이 파일 내용 붙여넣기 → Run
--   (이미 2026-05-11에 1회 실행 완료 — 재현/추적용 기록 파일)
--
-- 안전성:
--   BEGIN/COMMIT 트랜잭션으로 묶음 — 중간 실패 시 전체 롤백.
--   기존 5건은 ACTIVE → APPROVED로 의미 보존(카카오 가입자=승인된 활성 사용자).
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── 1) 기존 'ACTIVE' / NULL 값을 명세의 'APPROVED'로 매핑 ──
-- 기존 카카오 가입자는 모두 활성 상태였으므로 APPROVED와 의미 일치
UPDATE public.users
SET status = 'APPROVED'
WHERE status = 'ACTIVE' OR status IS NULL;

-- ── 2) 타입 변환 전 기본값 제거 ─────────────────────────
-- varchar 'ACTIVE' 기본값이 걸려 있어 ENUM 변환을 차단함
ALTER TABLE public.users
  ALTER COLUMN status DROP DEFAULT;

-- ── 3) varchar → user_status ENUM 변환 ──────────────────
-- USING 절로 명시 캐스팅 (모든 행이 PENDING/APPROVED/REJECTED 중 하나여야 성공)
ALTER TABLE public.users
  ALTER COLUMN status TYPE user_status
  USING status::user_status;

-- ── 4) ENUM 타입으로 기본값 재설정 ──────────────────────
-- OWNER만 PENDING으로 들어가므로 일반 가입자는 즉시 APPROVED
ALTER TABLE public.users
  ALTER COLUMN status SET DEFAULT 'APPROVED'::user_status;

-- ── 5) NOT NULL 제약 추가 ────────────────────────────────
-- 5/7 결정: 모든 사용자는 반드시 status 보유
ALTER TABLE public.users
  ALTER COLUMN status SET NOT NULL;

COMMIT;

-- ══════════════════════════════════════════════════════════
-- 사후 검증 쿼리:
--   SELECT column_name, data_type, udt_name, column_default, is_nullable
--   FROM information_schema.columns
--   WHERE table_schema='public' AND table_name='users' AND column_name='status';
--
-- 기대 결과:
--   data_type = USER-DEFINED
--   udt_name  = user_status
--   column_default = 'APPROVED'::user_status
--   is_nullable = NO
-- ══════════════════════════════════════════════════════════
