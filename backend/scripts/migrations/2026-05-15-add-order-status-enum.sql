-- ══════════════════════════════════════════════════════════
-- 마이그레이션: order_status ENUM 확장 (2026-05-15)
--
-- 배경 (사장님 결정):
--   배민·쿠팡이츠 패턴 = 결제 후 사장 수락/거절 + 자동 환불.
--   주문 진행 5단계 가시화 (배민 stepper 스타일) 를 위해 ENUM 확장 필요.
--
-- 현재 (CLAUDE.md 정의):
--   order_status = PENDING / ACCEPTED / PREPARING / DONE / CANCELLED
--
-- 확장 후:
--   PENDING  — 주문 생성 직후 (결제 전, 임시)
--   PAID     — 결제 완료 (손님이 결제 위젯 통과, 사장 처리 대기)
--   ACCEPTED — 사장 수락 (자동 통과 가능, 명시 단계는 후속)
--   PREPARING— 조리 중
--   READY    — 조리 완료 / 픽업 대기
--   COMPLETED— 손님 픽업 완료 (배민의 '완료' 단계)
--   DONE     — (레거시) — 기존 코드와 호환 유지
--   CANCELLED— 사장 거절 + 환불 완료
--
-- 안전성:
--   - ADD VALUE IF NOT EXISTS (PostgreSQL 12+) — 멱등성
--   - 기존 DONE 값 유지 — 코드에서 점차 COMPLETED 로 마이그레이션
--   - 기존 행 영향 0
--
-- 사장님 정책 (plan):
--   Q1: ENUM 5단계 확장 OK ✓
--   Q2: 거절 가능 = PAID + ACCEPTED 두 상태 (PREPARING 후 차단)
--   Q3: 원자성 — 토스 cancel 성공 시에만 CANCELLED 적용 (pos.service.ts:cancelOrder)
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

BEGIN;

-- ── PAID 추가 ────────────────────────────────────────────
-- 결제 완료 직후 상태. 사장 수락 전 단계.
ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'PAID';

-- ── READY 추가 ───────────────────────────────────────────
-- 조리 완료 / 픽업 대기 상태. 배민 stepper 의 '픽업 준비' 단계.
ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'READY';

-- ── COMPLETED 추가 ───────────────────────────────────────
-- 손님 픽업 완료. 배민 stepper 의 '완료' 단계.
-- DONE 과 의미상 중복이지만 기존 코드 호환을 위해 둘 다 유지.
-- 신규 주문은 COMPLETED 사용 권장, 기존 DONE 행은 그대로.
ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'COMPLETED';

COMMIT;

-- ── 검증 (실행 후 확인) ──────────────────────────────────
-- SELECT enumlabel FROM pg_enum WHERE enumtypid =
--   (SELECT oid FROM pg_type WHERE typname = 'order_status')
-- ORDER BY enumsortorder;
--
-- 기대값:
--   PENDING / PAID / ACCEPTED / PREPARING / READY / DONE / COMPLETED / CANCELLED
