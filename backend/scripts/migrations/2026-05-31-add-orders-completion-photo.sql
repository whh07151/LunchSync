-- ══════════════════════════════════════════════════════════
-- 파일 역할: orders.completion_photo_url 컬럼 추가 + Storage 버킷 생성
--
-- 배경 (WOW 포인트 2순위):
--   사장이 POS 에서 "조리 완료" 옆 카메라 아이콘 탭 → 단말 카메라 1장 → 손님
--   주문 추적 화면에 페이드인. "실제 음식 사진을 사장님이 직접" 이라는 신뢰
--   포인트가 시연 임팩트.
--
-- 적용 순서:
--   1) ALTER TABLE — orders 에 nullable TEXT 컬럼 추가 (멱등)
--   2) INSERT INTO storage.buckets — 'order-photos' public 버킷 생성
--   3) RLS 정책 — public 읽기 허용, write 는 service_role 만 (백엔드 경유)
--
-- 적용 위치: Supabase Dashboard SQL Editor 에서 일괄 실행.
--   (storage 정책은 service_role 이 아닌 일반 connection 에서는 변경 불가
--    할 수 있어 Supabase 콘솔에서 수동 실행 필수)
-- ══════════════════════════════════════════════════════════

-- ── 1. orders.completion_photo_url 컬럼 추가 ───────────
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS completion_photo_url TEXT;

COMMENT ON COLUMN orders.completion_photo_url IS
  '사장이 POS 에서 업로드한 조리 완료 사진 URL (Supabase Storage order-photos 버킷 public URL).';

-- ── 2. Storage 버킷 생성 (public read) ─────────────────
-- 멱등: bucket id 중복 시 무시.
INSERT INTO storage.buckets (id, name, public)
VALUES ('order-photos', 'order-photos', true)
ON CONFLICT (id) DO NOTHING;

-- ── 3. RLS 정책 ────────────────────────────────────────
-- public 읽기 — 손님 어플이 public URL 로 GET 할 때 anon 키도 통과해야 함.
-- write — 백엔드 service_role 만 (POST /api/pos/orders/:id/completion-photo 가 경유).
--   service_role 은 RLS bypass 라 별도 INSERT/UPDATE 정책 없어도 동작하지만,
--   기본 deny 정책(아무것도 정의 안 함)이 익명 업로드는 차단해 안전.

-- 기존 같은 이름 정책이 있으면 제거 후 재생성 (멱등)
DROP POLICY IF EXISTS "order-photos public read" ON storage.objects;

CREATE POLICY "order-photos public read"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'order-photos');

-- ── 검증 쿼리 (사용자가 수동 실행하여 적용 여부 확인) ──
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'orders' AND column_name = 'completion_photo_url';
-- SELECT id, public FROM storage.buckets WHERE id = 'order-photos';
