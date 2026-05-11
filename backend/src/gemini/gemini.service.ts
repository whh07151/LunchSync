import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// ══════════════════════════════════════════════════════════
// 파일 역할: Google Gemini AI 메뉴 자동 생성 서비스
//
// 사용 시점:
//   - 카카오 로컬 API 로 식당은 발견되지만 네이버 비공식 API 가 메뉴를
//     반환하지 못한 경우 (네이버 차단/지역 IP 거부 등) Gemini 가 식당명+카테고리
//     기반으로 추정 메뉴 5~8개를 생성한다.
//
// 응답 형식 (각 메뉴):
//   { name: string, price: number, ingredients: string[], allergens: string[] }
//
// 알레르기 목록 (한국 식품의약품안전처 8대):
//   "땅콩", "갑각류", "유제품", "계란", "밀", "대두", "생선", "조개류"
//
// 신뢰성:
//   AI 추정이라 실제 식당 메뉴와 100% 일치하지 않음. menu_items.source 가
//   'AI_GEMINI' 로 저장되어 사장이 추후 수정/삭제할 수 있다.
//
// 비용:
//   Gemini Flash 무료 티어 (일 1500건). 캡스톤 시연용 충분.
// ══════════════════════════════════════════════════════════

export interface GeminiMenuItem {
  name: string;
  price: number;
  ingredients: string[];
  allergens: string[];
}

@Injectable()
export class GeminiService {
  private readonly logger = new Logger(GeminiService.name);
  private readonly apiKey: string | undefined;
  private readonly model: string;

  constructor(private readonly config: ConfigService) {
    this.apiKey = this.config.get<string>('GEMINI_API_KEY');
    this.model = this.config.get<string>('GEMINI_MODEL') ?? 'gemini-2.0-flash';
    if (!this.apiKey) {
      this.logger.warn(
        'GEMINI_API_KEY 미설정 — 메뉴 AI 폴백 비활성화',
      );
    }
  }

  // ── 식당 정보 기반 메뉴 5~8개 자동 생성 ───────────────
  // 실패 시 빈 배열 반환 (호출측이 폴백 가능).
  async generateMenuForRestaurant(params: {
    name: string;
    category?: string;
  }): Promise<GeminiMenuItem[]> {
    if (!this.apiKey) return [];

    const prompt = this.buildPrompt(params.name, params.category);

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
            temperature: 0.4, // 너무 랜덤하지 않게
            maxOutputTokens: 1500,
            responseMimeType: 'application/json',
          },
        }),
        signal: AbortSignal.timeout(15_000), // 15초
      });

      if (!res.ok) {
        const errText = await res.text().catch(() => '');
        this.logger.warn(
          `Gemini API 응답 실패 ${res.status}: ${errText.slice(0, 200)}`,
        );
        return [];
      }

      const data = await res.json();
      // 응답 구조: candidates[0].content.parts[0].text 에 JSON 문자열
      const text =
        data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

      if (!text) {
        this.logger.warn('Gemini 응답이 비어있음');
        return [];
      }

      return this.parseMenuResponse(text);
    } catch (err) {
      this.logger.warn(
        `Gemini 호출 예외: ${(err as Error).message}`,
      );
      return [];
    }
  }

  // ── 프롬프트 빌더 ─────────────────────────────────────
  private buildPrompt(name: string, category?: string): string {
    const categoryHint = category ? ` (${category})` : '';
    return `당신은 한국 식당 메뉴 전문가입니다. 다음 식당의 대표 메뉴 5~8개를 추정해서 JSON 배열로 반환하세요.

식당: ${name}${categoryHint}

규칙:
1. JSON 배열만 반환. 다른 설명이나 마크다운 백틱 없이.
2. 각 메뉴는 다음 필드를 포함:
   - name: 메뉴 이름 (한글)
   - price: 가격 (원 단위 정수, 한국 식당 평균 5000~25000원 범위)
   - ingredients: 주재료 배열 (한글, 2~5개)
   - allergens: 알레르기 정보 배열 (해당 시만, 다음 8가지에서만 선택)
     ["땅콩", "갑각류", "유제품", "계란", "밀", "대두", "생선", "조개류"]
3. 식당 카테고리/이름에 어울리는 실제 한국 메뉴.
4. 알레르기 정보가 없는 메뉴는 빈 배열 [].

예시 형식:
[
  {"name": "김치찌개", "price": 9000, "ingredients": ["돼지고기", "김치", "두부"], "allergens": ["대두"]},
  {"name": "된장찌개", "price": 9000, "ingredients": ["된장", "두부", "감자"], "allergens": ["대두"]}
]

JSON 배열만 반환:`;
  }

  // ── 응답 JSON 파싱 ────────────────────────────────────
  // Gemini 가 마크다운 백틱이나 추가 텍스트를 붙일 수 있어서 정규식으로 JSON 추출.
  private parseMenuResponse(raw: string): GeminiMenuItem[] {
    try {
      // 1) 마크다운 백틱 제거
      let cleaned = raw.trim();
      cleaned = cleaned.replace(/^```(?:json)?\s*/, '').replace(/```\s*$/, '');

      // 2) 첫 [ 부터 마지막 ] 까지만 추출
      const start = cleaned.indexOf('[');
      const end = cleaned.lastIndexOf(']');
      if (start === -1 || end === -1) {
        this.logger.warn('Gemini 응답에서 JSON 배열 미발견');
        return [];
      }
      const json = cleaned.slice(start, end + 1);
      const parsed = JSON.parse(json) as unknown;

      if (!Array.isArray(parsed)) return [];

      // 3) 각 항목 검증 (방어적 파싱)
      const validAllergens = new Set([
        '땅콩',
        '갑각류',
        '유제품',
        '계란',
        '밀',
        '대두',
        '생선',
        '조개류',
      ]);

      return parsed
        .filter((item) => typeof item === 'object' && item !== null)
        .map((item: any) => ({
          name: String(item.name ?? '').trim(),
          price: Math.max(0, Math.floor(Number(item.price) || 0)),
          ingredients: Array.isArray(item.ingredients)
            ? item.ingredients
                .filter((x: unknown) => typeof x === 'string')
                .map((x: string) => x.trim())
                .filter((x: string) => x.length > 0)
            : [],
          allergens: Array.isArray(item.allergens)
            ? item.allergens
                .filter(
                  (x: unknown) =>
                    typeof x === 'string' && validAllergens.has(x.trim()),
                )
                .map((x: string) => x.trim())
            : [],
        }))
        .filter((m) => m.name.length > 0 && m.price > 0);
    } catch (err) {
      this.logger.warn(
        `Gemini JSON 파싱 실패: ${(err as Error).message}`,
      );
      return [];
    }
  }
}
