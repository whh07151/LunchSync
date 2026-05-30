// ══════════════════════════════════════════════════════════
// 파일 역할: WOW 포인트 #3 "점심 케미 매트릭스" 비즈니스 로직
//
// 컨셉:
//   세션 멤버 N명의 과거 점심 카테고리 (최근 30일 orders + 투표 winner 식당)
//   취향을 분석해 그룹의 "케미 점수(0~100)" 와 한 줄 요약을 Gemini AI 로 생성.
//   추천 리스트 화면 상단에 카드로 노출 → "오늘 점심 누가 있어요" 감성 강화.
//
// 데이터 파이프라인:
//   1. session_members 에서 멤버 user_id 전원 수집
//   2. 멤버별로:
//        a) orders join restaurants(category) — 최근 30일, COMPLETED/DONE 상태
//        b) votes join restaurants(category)  — 멤버가 한 모든 투표 + 세션의
//           winner_restaurant_id 카테고리 가산
//   3. 카테고리 빈도 합산 → top 3 추출
//   4. Gemini 프롬프트에 데이터 전달 → { score, label, tone, topCategories } JSON
//
// 캐시:
//   in-memory Map<sessionId, { result, expiresAt }>, TTL 30분.
//   세션 멤버 구성/주문이 거의 안 변하는 점심 한 끼 동안 동일 응답 재사용.
//
// 장애 차단 (요구사항):
//   Gemini API 실패 / 키 없음 / 데이터 0건 → null 반환. 컨트롤러는 그대로
//   { success: true, data: null } 로 응답하고, Flutter 측이 null 이면
//   카드 자체를 미노출 (이상 표시 0건). 사용자 경험에 부정 영향 없음.
//
// 비용:
//   Gemini Flash 무료 티어 사용. 세션당 30분 1회 호출 → 캡스톤 시연 충분.
// ══════════════════════════════════════════════════════════

import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';

// 케미 응답 DTO — 컨트롤러가 그대로 JSON 직렬화해서 내려줌.
export interface ChemistryResult {
  score: number;        // 0~100 정수
  label: string;        // "매콤+가성비형" 같은 그룹 성격 한 줄 라벨
  tone: string;         // 카드 색상 톤 (warm | cool | neutral) — 프론트 색 분기
  topCategories: string[]; // 상위 3개 카테고리 칩
}

// 캐시 엔트리 — 30분 후 만료.
interface CacheEntry {
  result: ChemistryResult;
  expiresAt: number;
}

@Injectable()
export class ChemistryService {
  private readonly logger = new Logger(ChemistryService.name);
  private readonly apiKey: string | undefined;
  private readonly model: string;

  // 세션 단위 30분 캐시. Redis 미도입이므로 in-memory Map 으로 폴백.
  // 프로세스 재시작 시 자연 무효화 → 별도 invalidation 로직 불필요.
  private readonly cache = new Map<string, CacheEntry>();
  private static readonly CACHE_TTL_MS = 30 * 60 * 1000; // 30분

  constructor(
    private readonly supabase: SupabaseService,
    private readonly config: ConfigService,
  ) {
    this.apiKey = this.config.get<string>('GEMINI_API_KEY');
    this.model = this.config.get<string>('GEMINI_MODEL') ?? 'gemini-2.0-flash';
    if (!this.apiKey) {
      this.logger.warn(
        'GEMINI_API_KEY 미설정 — 케미 매트릭스가 폴백(룰베이스)로 동작합니다.',
      );
    }
  }

  // ── GET /sessions/:id/chemistry 메인 진입점 ─────────────
  // 캐시 hit → 즉시 응답. miss → 데이터 수집 + Gemini 호출 후 캐싱.
  // 멤버/주문이 0건이면 폴백 룰베이스 결과(50점) 반환 — 카드를 굳이 숨길 필요 없음.
  async getChemistry(sessionId: string): Promise<ChemistryResult | null> {
    // 1) 캐시 hit 우선 확인.
    const cached = this.cache.get(sessionId);
    if (cached && cached.expiresAt > Date.now()) {
      this.logger.debug(`[Chemistry] 캐시 hit session=${sessionId}`);
      return cached.result;
    }

    // 2) 세션 존재 검증 — 잘못된 sessionId 면 404 명확히 던짐.
    const { data: session, error: sessionErr } = await this.supabase.client
      .from('sessions')
      .select('id, winner_restaurant_id')
      .eq('id', sessionId)
      .single();
    if (sessionErr || !session) {
      throw new NotFoundException('세션을 찾을 수 없습니다.');
    }

    // 3) 멤버 id 수집.
    const { data: memberRows } = await this.supabase.client
      .from('session_members')
      .select('user_id')
      .eq('session_id', sessionId);
    const memberIds = (memberRows ?? []).map((m) => m.user_id as string);
    if (memberIds.length === 0) {
      // 멤버 0명 — 의미 있는 케미 불가.
      // 카드 미노출 의도이므로 null 반환.
      return null;
    }

    // 4) 카테고리 빈도 합산 (orders + votes + winner 식당).
    const categoryFreq = await this.collectCategoryFrequency(
      memberIds,
      sessionId,
      (session as { winner_restaurant_id: string | null }).winner_restaurant_id,
    );

    // 5) Gemini 호출 → 실패하면 룰베이스 폴백.
    //    데이터가 비어있어도 폴백은 동작(중립 응답).
    let result: ChemistryResult | null = null;
    if (this.apiKey) {
      result = await this.callGemini(categoryFreq, memberIds.length);
    }
    if (!result) {
      result = this.ruleBasedFallback(categoryFreq, memberIds.length);
    }

    // 6) 캐시 저장 (30분 TTL).
    this.cache.set(sessionId, {
      result,
      expiresAt: Date.now() + ChemistryService.CACHE_TTL_MS,
    });

    return result;
  }

  // ── 카테고리 빈도 수집기 ─────────────────────────────────
  // 최근 30일 orders (COMPLETED/DONE) + 멤버들의 votes(투표한 식당) + 세션 winner 가산.
  // restaurants(category) join 으로 한 번에 카테고리만 가져옴 — N+1 회피.
  //
  // 실패 (Supabase 에러) 시 빈 Map → 룰베이스/Gemini 가 중립 응답으로 fallback.
  private async collectCategoryFrequency(
    memberIds: string[],
    sessionId: string,
    winnerRestaurantId: string | null,
  ): Promise<Map<string, number>> {
    const freq = new Map<string, number>();
    const since = new Date(Date.now() - 30 * 86400000).toISOString();

    // (a) orders → restaurants.category
    //   COMPLETED 또는 DONE 인 주문만 — 실제로 먹은 점심 카운트.
    try {
      const { data: orderRows } = await this.supabase.client
        .from('orders')
        .select('restaurants(category)')
        .in('user_id', memberIds)
        .gte('created_at', since)
        .in('status', ['COMPLETED', 'DONE']);

      for (const row of (orderRows ?? []) as Array<{
        restaurants:
          | { category: string | null }
          | Array<{ category: string | null }>
          | null;
      }>) {
        const cats = this.extractCategory(row.restaurants);
        for (const c of cats) {
          freq.set(c, (freq.get(c) ?? 0) + 1);
        }
      }
    } catch (err) {
      this.logger.warn(
        `[Chemistry] orders 카테고리 수집 실패: ${(err as Error).message}`,
      );
    }

    // (b) votes → 멤버가 투표한 식당의 카테고리도 가산.
    //   투표가 의사 표현이라 실제 주문보다 가중치는 약간 낮지만(0.5),
    //   캡스톤 시연 환경(주문 데이터 부족) 에선 votes 가 유일한 신호인 경우 많음.
    try {
      const { data: voteRows } = await this.supabase.client
        .from('votes')
        .select('restaurants(category)')
        .in('user_id', memberIds);

      for (const row of (voteRows ?? []) as Array<{
        restaurants:
          | { category: string | null }
          | Array<{ category: string | null }>
          | null;
      }>) {
        const cats = this.extractCategory(row.restaurants);
        for (const c of cats) {
          // 0.5 가중 — 정수 합산을 위해 freq 는 0.5 단위 부동소수점 허용.
          freq.set(c, (freq.get(c) ?? 0) + 0.5);
        }
      }
    } catch (err) {
      this.logger.warn(
        `[Chemistry] votes 카테고리 수집 실패: ${(err as Error).message}`,
      );
    }

    // (c) 이 세션의 winner 식당 카테고리도 +1 — "오늘 우리가 고른 식당" 강조.
    if (winnerRestaurantId) {
      try {
        const { data: winner } = await this.supabase.client
          .from('restaurants')
          .select('category')
          .eq('id', winnerRestaurantId)
          .single();
        const cats = this.extractCategory(winner);
        for (const c of cats) {
          freq.set(c, (freq.get(c) ?? 0) + 1);
        }
      } catch (err) {
        // 미사용 — 디버그 로그만.
        this.logger.debug(
          `[Chemistry] winner 카테고리 조회 실패(무시): ${(err as Error).message}`,
        );
      }
      // sessionId 는 로그 컨텍스트 용도 — 디버그.
      this.logger.debug(`[Chemistry] winner 가산 session=${sessionId}`);
    }

    return freq;
  }

  // Supabase 의 nested select 응답이 1:1 객체일 수도, 1:N 배열일 수도 있어 양쪽 방어.
  // restaurants 가 null 이거나 category 가 비어있는 행은 무시.
  private extractCategory(
    rel:
      | { category: string | null }
      | Array<{ category: string | null }>
      | null,
  ): string[] {
    if (!rel) return [];
    const list = Array.isArray(rel) ? rel : [rel];
    return list
      .map((x) => (x?.category ?? '').trim())
      .filter((x) => x.length > 0);
  }

  // ── 폴백: 룰베이스 케미 산출 ────────────────────────────
  // Gemini 비활성/실패 시 사용. 단순하지만 안정적인 휴리스틱:
  //   · top 1 카테고리 점유율이 높을수록 점수 ↑ (취향 일치)
  //   · 데이터 0건이면 50점 / "조사 중" 라벨로 카드는 그대로 노출.
  private ruleBasedFallback(
    freq: Map<string, number>,
    memberCount: number,
  ): ChemistryResult {
    const sorted = [...freq.entries()].sort((a, b) => b[1] - a[1]);
    const total = [...freq.values()].reduce((s, v) => s + v, 0);
    const top3 = sorted.slice(0, 3).map(([k]) => k);

    if (total < 1 || top3.length === 0) {
      // 카테고리 신호 자체가 없으면 중립 응답.
      return {
        score: 50,
        label: '아직 데이터가 적어요',
        tone: 'neutral',
        topCategories: [],
      };
    }

    const topRatio = sorted[0][1] / total; // 0~1
    // 멤버 수가 많을수록 일치율이 떨어지기 쉬워 보너스 가산.
    const memberBonus = Math.min(10, memberCount * 2);
    const score = Math.round(50 + topRatio * 40 + memberBonus);

    // 톤은 상위 카테고리 키워드로 단순 분기.
    const topCat = top3[0];
    let tone: ChemistryResult['tone'] = 'neutral';
    if (/한식|중식|분식|찌개|매콤/i.test(topCat)) tone = 'warm';
    else if (/일식|샐러드|아시안|카페/i.test(topCat)) tone = 'cool';

    return {
      score: Math.max(0, Math.min(100, score)),
      label: `${topCat} 선호 그룹`,
      tone,
      topCategories: top3,
    };
  }

  // ── Gemini 호출 ──────────────────────────────────────────
  // 실패하면 null 반환 → 호출측이 룰베이스 폴백.
  // 응답은 score/label/tone/topCategories 4필드 JSON.
  private async callGemini(
    freq: Map<string, number>,
    memberCount: number,
  ): Promise<ChemistryResult | null> {
    if (!this.apiKey) return null;

    const sorted = [...freq.entries()].sort((a, b) => b[1] - a[1]);
    const topPairs = sorted
      .slice(0, 8) // 너무 많이 보내봐야 노이즈 — 상위 8개만.
      .map(([cat, n]) => `${cat}: ${n.toFixed(1)}회`)
      .join(', ');

    const prompt = this.buildPrompt(topPairs, memberCount);

    try {
      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/${this.model}` +
        `:generateContent?key=${this.apiKey}`;

      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.7,        // 한 줄 카피는 살짝 창의적이게.
            maxOutputTokens: 400,    // JSON 짧음 — 토큰 절약.
            responseMimeType: 'application/json',
          },
        }),
        signal: AbortSignal.timeout(10_000), // 10초 — 추천 리스트 진입 직후 빠른 응답.
      });

      if (!res.ok) {
        this.logger.warn(`[Chemistry] Gemini ${res.status}`);
        return null;
      }

      const data = await res.json();
      const text =
        data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
      if (!text) return null;

      return this.parseGeminiResponse(text);
    } catch (err) {
      this.logger.warn(`[Chemistry] Gemini 예외: ${(err as Error).message}`);
      return null;
    }
  }

  // 프롬프트는 가능한 한 짧게 — 캡스톤 비용 최소화.
  // JSON 강제 + 한국어 label/tone enum 명확화.
  private buildPrompt(topPairs: string, memberCount: number): string {
    return `당신은 한국 점심 추천 데이터 분석가입니다. 다음은 ${memberCount}명 그룹 멤버들의 최근 30일 점심 카테고리 빈도입니다.

데이터: ${topPairs || '(데이터 없음)'}

이 그룹의 "점심 케미 점수(0~100)"와 한 줄 요약 라벨, 톤 색상을 JSON으로만 응답하세요. 다른 설명/마크다운 없이.

필드:
- score: 0~100 정수 (취향 일치도 + 점심 다양성 가산. 일치도 높으면 80+, 데이터 빈약하면 50 부근)
- label: "매콤+가성비형", "건강식 사랑꾼", "다양성 폭발 그룹" 같은 한국어 한 줄 (15자 이내)
- tone: "warm" | "cool" | "neutral" 중 하나 (한식/매콤=warm, 일식/샐러드=cool, 그 외=neutral)
- topCategories: 상위 3개 카테고리 한글 배열 (입력 데이터에서만 선택, 없으면 빈 배열)

예시:
{"score": 87, "label": "매콤+가성비형", "tone": "warm", "topCategories": ["한식", "분식", "중식"]}

JSON 객체만 반환:`;
  }

  // 응답 텍스트에서 JSON 객체 1개를 안전 파싱.
  // 마크다운 백틱 / 추가 텍스트가 섞여도 첫 { ... } 만 추출.
  private parseGeminiResponse(raw: string): ChemistryResult | null {
    try {
      let cleaned = raw.trim();
      cleaned = cleaned.replace(/^```(?:json)?\s*/, '').replace(/```\s*$/, '');
      const start = cleaned.indexOf('{');
      const end = cleaned.lastIndexOf('}');
      if (start === -1 || end === -1) return null;
      const parsed = JSON.parse(cleaned.slice(start, end + 1)) as Record<
        string,
        unknown
      >;

      // 방어적 정규화 — Gemini 가 살짝 다른 형태로 응답해도 화면이 깨지지 않게.
      const score = Math.max(
        0,
        Math.min(100, Math.round(Number(parsed.score) || 0)),
      );
      const label = String(parsed.label ?? '').trim().slice(0, 30) || '점심 케미';
      const toneRaw = String(parsed.tone ?? 'neutral').trim().toLowerCase();
      const tone: ChemistryResult['tone'] =
        toneRaw === 'warm' || toneRaw === 'cool' ? toneRaw : 'neutral';
      const topCategories = Array.isArray(parsed.topCategories)
        ? (parsed.topCategories as unknown[])
            .filter((x): x is string => typeof x === 'string')
            .map((x) => x.trim())
            .filter((x) => x.length > 0)
            .slice(0, 3)
        : [];

      return { score, label, tone, topCategories };
    } catch (err) {
      this.logger.warn(
        `[Chemistry] Gemini JSON 파싱 실패: ${(err as Error).message}`,
      );
      return null;
    }
  }
}
