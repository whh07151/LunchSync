// ══════════════════════════════════════════════════════════
// 파일 역할: price-range-normalizer 유닛 테스트
//
// 검증 목표:
//   1. Gemini 1~5 척도 입력 → 매핑 테이블 값 반환
//   2. 카카오 크롤 6~999 입력 → × 1000 환산
//   3. 시드 1000+ 입력 → 그대로 반환
//   4. null / undefined / 0 / 음수 → null (호출측 skip)
//
// 회귀 방지 포인트:
//   - 시드값 5500 입력 시 5500 (원)이 나와야 함 (5천5백만원 폭주 회귀 차단)
//   - 크롤값 13 입력 시 13000 (원)이 나와야 함
//   - Gemini 척도 3 입력 시 15000 (원)이 나와야 함
// ══════════════════════════════════════════════════════════

import { normalizePriceRangeToWon } from './price-range-normalizer';

describe('normalizePriceRangeToWon', () => {
  describe('① Gemini 1~5 척도', () => {
    it('1 → 5,000원 (저렴)', () => {
      expect(normalizePriceRangeToWon(1)).toBe(5000);
    });
    it('2 → 10,000원', () => {
      expect(normalizePriceRangeToWon(2)).toBe(10000);
    });
    it('3 → 15,000원 (보통)', () => {
      expect(normalizePriceRangeToWon(3)).toBe(15000);
    });
    it('4 → 25,000원', () => {
      expect(normalizePriceRangeToWon(4)).toBe(25000);
    });
    it('5 → 35,000원 (고급)', () => {
      expect(normalizePriceRangeToWon(5)).toBe(35000);
    });
  });

  describe('② 카카오 크롤 6~999 (1000원 단위)', () => {
    it('7 → 7,000원', () => {
      expect(normalizePriceRangeToWon(7)).toBe(7000);
    });
    it('13 → 13,000원 (회귀 케이스)', () => {
      expect(normalizePriceRangeToWon(13)).toBe(13000);
    });
    it('999 → 999,000원 (경계값)', () => {
      expect(normalizePriceRangeToWon(999)).toBe(999000);
    });
  });

  describe('③ 시드 1000+ (실제 원 단위)', () => {
    it('1000 → 1,000원 (하한 경계)', () => {
      expect(normalizePriceRangeToWon(1000)).toBe(1000);
    });
    it('5500 → 5,500원 (회귀 케이스: 시드 분식)', () => {
      expect(normalizePriceRangeToWon(5500)).toBe(5500);
    });
    it('8000 → 8,000원', () => {
      expect(normalizePriceRangeToWon(8000)).toBe(8000);
    });
    it('15000 → 15,000원 (시드 한식)', () => {
      expect(normalizePriceRangeToWon(15000)).toBe(15000);
    });
    it('25000 → 25,000원 (시드 일식)', () => {
      expect(normalizePriceRangeToWon(25000)).toBe(25000);
    });
  });

  describe('④ 누락/이상값 → null (호출측 skip)', () => {
    it('null → null', () => {
      expect(normalizePriceRangeToWon(null)).toBeNull();
    });
    it('undefined → null', () => {
      expect(normalizePriceRangeToWon(undefined)).toBeNull();
    });
    it('0 → null', () => {
      expect(normalizePriceRangeToWon(0)).toBeNull();
    });
    it('음수(-100) → null', () => {
      expect(normalizePriceRangeToWon(-100)).toBeNull();
    });
  });
});
