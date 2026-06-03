-- ══════════════════════════════════════════════════════════
-- 2026-06-03: orders.updated_at 자동 갱신 트리거
--
-- 배경:
--   pos.service.ts 의 여러 경로(updateOrderStatus, cancelOrder, refundOrderSim,
--   chargeViaPosToss)가 orders.status 를 UPDATE 하면서 updated_at 은 건드리지
--   않았다. 코드 주석(toss-pos-charge)은 "updated_at 트리거가 NOW() 로 자동
--   갱신"을 가정했으나, 실제 Supabase 에 해당 트리거가 없어 updated_at 이
--   생성시각(created_at) 그대로 고정되는 버그가 있었다.
--   (2026-06-03 라이브 확인: 모든 주문 updatedAt == createdAt == 2026-05-25)
--
-- 영향:
--   · POS 결제관리 "오늘 결제" 집계가 updated_at 기준이라 과거 결제를 못 잡음
--   · POS 통계 "평균 처리시간(created_at → updated_at)" 이 항상 0분
--
-- 해결:
--   ① 코드(pos.service.ts)에서 status 변경 4곳에 updated_at 명시적 세팅 (즉효)
--   ② 본 트리거로 orders 의 모든 UPDATE 에 updated_at = NOW() 자동 적용 (근본)
--
-- 멱등(CREATE OR REPLACE + DROP IF EXISTS). Supabase 대시보드 SQL Editor 에서 1회 실행.
-- ══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION set_orders_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_orders_updated_at ON orders;
CREATE TRIGGER trg_orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION set_orders_updated_at();
