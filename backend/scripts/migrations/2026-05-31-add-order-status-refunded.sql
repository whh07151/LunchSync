-- ══════════════════════════════════════════════════════════
-- 파일 역할: order_status ENUM 에 REFUNDED 값 추가 (POS-09 / OW-10 안전망)
--
-- 배경:
--   POS-09 (LSPOS) + OW-10 (사장 결제 확인) 둘 다 환불 시뮬을
--   orders.status = 'REFUNDED' 로 표현한다. 코드는 단순 UPDATE 라
--   ENUM 제약이 있으면 22P02 (invalid_text_representation) 로 실패.
--
-- 적용 패턴:
--   Postgres ALTER TYPE … ADD VALUE 는 IF NOT EXISTS 보호가 있어
--   재실행해도 안전 (Postgres 9.6+). 트랜잭션 안에서는 못 실행하므로
--   single statement 로만 둔다.
-- ══════════════════════════════════════════════════════════

ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'REFUNDED';
