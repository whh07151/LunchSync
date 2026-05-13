-- ══════════════════════════════════════════════════════════
-- 마이그레이션: restaurants 테이블에 rating 컬럼 추가
--
-- 작성일: 2026-05-14
-- 배경:
--   사장님 피드백 — "네이버나 구글로 식당 평점 조사한 거 맞아?"
--   현재 CrawlService.fetchNaverPlaceDetail() 가 네이버 응답에서
--   parseFloat(firstPlace.reviewScore) 로 평점을 수집하지만, DB
--   restaurants 테이블에 rating 컬럼이 없어 수집한 값이 그대로 버려졌다.
--
-- 영향:
--   - 식당 카드/상세 화면에서 "⭐ 4.2" 표기 가능
--   - 추후 추천 엔진(CORE-07) 의 점수 가중치로도 활용
--
-- 자료형:
--   NUMERIC(2,1) — 0.0 ~ 9.9 범위 (실제 의미는 0.0 ~ 5.0)
--   ※ 네이버 평점은 0.00 ~ 5.00 이지만 소수점 1자리로 충분.
--
-- 실행 위치:
--   Supabase Dashboard → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

-- 식당 평점 컬럼 추가 (네이버 플레이스 reviewScore 저장용)
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS rating NUMERIC(2,1);
COMMENT ON COLUMN restaurants.rating IS '네이버 플레이스 평점 (0.0~5.0)';
