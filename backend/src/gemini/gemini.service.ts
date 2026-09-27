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

// ── 좌표 기반 가상 식당 폴백용 타입 (2026-05-12 추가) ──────
// 카카오 로컬 API 가 0개를 반환하는 극단 케이스(차단/오지)에
// Gemini 가 그 좌표 동네에 어울리는 가상 식당을 만들어 준다.
// 식당 자체(이름/카테고리/가격대) + 그 식당의 대표 메뉴를 한 번에 생성.
export interface GeminiGeneratedMenu {
  name: string;
  price: number;
  category: string; // rice | noodle | snack | soup | drink | main
  ingredients: string[];
  allergens: string[];
}

export interface GeminiGeneratedRestaurant {
  name: string;           // 동네 분위기에 어울리는 가상 식당명
  category: string;       // 한식 | 중식 | 일식 | 양식 | 분식 | 카페 | 아시안 | 패스트푸드
  priceRange: number;     // 1~5 (1: 저렴, 5: 고급)
  addressHint: string;    // "강동구 길동" 같은 동네 표기 — 주소 컬럼 채우기 용도
  menus: GeminiGeneratedMenu[];
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
        this.logger.warn(`GEMINI_MENU_REQUEST_FAILED status=${res.status}`);
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
    } catch {
      this.logger.warn('GEMINI_MENU_REQUEST_EXCEPTION');
      return [];
    }
  }

  // ── 좌표 기반 가상 식당 N개 생성 (2026-05-12 추가) ────────
  // 카카오 0개 폴백 안전망. 동네 이름은 위경도로부터 직접 못 끌어내므로
  // 호출측이 areaHint (예: "강동구 길동", "강남역", "역삼동") 를 넘겨주면
  // 그 동네 분위기에 맞는 식당을 만든다. 비어있으면 일반 도심 식당을 만듦.
  //
  // 실패 시 빈 배열 반환 → 호출측이 추가 폴백 처리 가능.
  async generateRestaurantsForArea(params: {
    areaHint?: string;
    count?: number;
    categories?: string[]; // ex) ['한식', '분식', '일식', '양식', '중식']
  }): Promise<GeminiGeneratedRestaurant[]> {
    if (!this.apiKey) return [];

    const count = Math.max(1, Math.min(10, params.count ?? 5));
    const categories =
      params.categories ?? ['한식', '분식', '일식', '양식', '중식'];

    const prompt = this.buildAreaPrompt(
      params.areaHint ?? '도심 직장가',
      count,
      categories,
    );

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
            // 식당 이름은 약간의 다양성이 필요 → 메뉴 단독 호출보다 살짝 높음
            temperature: 0.6,
            // 식당 N개 × 메뉴 4~6개 → 응답 길이가 길어짐
            maxOutputTokens: 3500,
            responseMimeType: 'application/json',
          },
        }),
        signal: AbortSignal.timeout(20_000), // 20초 (메뉴 단건 15s 보다 여유)
      });

      if (!res.ok) {
        this.logger.warn(
          `GEMINI_RESTAURANT_REQUEST_FAILED status=${res.status}`,
        );
        return [];
      }

      const data = await res.json();
      const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
      if (!text) {
        this.logger.warn('Gemini 식당생성 응답이 비어있음');
        return [];
      }

      return this.parseRestaurantResponse(text);
    } catch {
      this.logger.warn('GEMINI_RESTAURANT_REQUEST_EXCEPTION');
      return [];
    }
  }

  // ── 식당 생성 프롬프트 빌더 ─────────────────────────────
  private buildAreaPrompt(
    areaHint: string,
    count: number,
    categories: string[],
  ): string {
    return `당신은 한국 식당 컨설턴트입니다. 다음 지역에 어울리는 가상의 식당 ${count}개를 JSON 배열로 반환하세요.

지역: ${areaHint}
카테고리 후보: ${categories.join(', ')}

규칙:
1. JSON 배열만 반환. 다른 설명/마크다운 백틱 없이.
2. 각 식당은 카테고리가 겹치지 않게 ${count}개 모두 다른 카테고리에서 선택 (가능하면).
3. 식당 이름은 한국 점심상권 분위기 (예: "맛있는 김밥나라", "역삼 한식담", "골목 라멘하우스" 같은 자연스러운 가상 상호).
4. 각 식당 필드:
   - name: 식당 이름 (한글, 중복 금지)
   - category: 위 카테고리 후보 중 하나
   - priceRange: 1~5 정수 (분식 1, 일식/한식 2~3, 양식 3~4)
   - addressHint: "${areaHint} OOOOO" 형식의 가상 주소 (예: "${areaHint} 중앙로 12")
   - menus: 4~6개 대표 메뉴 배열
5. menus 각 항목 필드:
   - name: 메뉴명 (한글)
   - price: 가격 (정수 원 단위, 5000~25000 범위)
   - category: rice | noodle | snack | soup | drink | main 중 하나
   - ingredients: 주재료 한글 배열 (2~5개)
   - allergens: 해당 시만, ["땅콩","갑각류","유제품","계란","밀","대두","생선","조개류"] 중에서만

예시 형식:
[
  {
    "name": "맛있는 김밥나라",
    "category": "분식",
    "priceRange": 1,
    "addressHint": "${areaHint} 골목길 22",
    "menus": [
      {"name":"참치김밥","price":4500,"category":"rice","ingredients":["참치","쌀","단무지"],"allergens":["생선"]}
    ]
  }
]

JSON 배열만 반환:`;
  }

  // ── 식당 생성 응답 파싱 ─────────────────────────────────
  // generateMenuForRestaurant 의 parseMenuResponse 와 같은 방어 전략을 식당 단위로 확장.
  private parseRestaurantResponse(raw: string): GeminiGeneratedRestaurant[] {
    try {
      let cleaned = raw.trim();
      cleaned = cleaned.replace(/^```(?:json)?\s*/, '').replace(/```\s*$/, '');

      const start = cleaned.indexOf('[');
      const end = cleaned.lastIndexOf(']');
      if (start === -1 || end === -1) {
        this.logger.warn('Gemini 식당생성 응답에서 JSON 배열 미발견');
        return [];
      }
      const json = cleaned.slice(start, end + 1);
      const parsed = JSON.parse(json) as unknown;
      if (!Array.isArray(parsed)) return [];

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
      const validMenuCategories = new Set([
        'rice',
        'noodle',
        'snack',
        'soup',
        'drink',
        'main',
      ]);

      return parsed
        .filter((r) => typeof r === 'object' && r !== null)
        .map((r: any): GeminiGeneratedRestaurant => {
          const menus: GeminiGeneratedMenu[] = Array.isArray(r.menus)
            ? r.menus
                .filter((m: unknown) => typeof m === 'object' && m !== null)
                .map((m: any) => ({
                  name: String(m.name ?? '').trim(),
                  price: Math.max(0, Math.floor(Number(m.price) || 0)),
                  category: validMenuCategories.has(String(m.category))
                    ? String(m.category)
                    : 'main',
                  ingredients: Array.isArray(m.ingredients)
                    ? m.ingredients
                        .filter((x: unknown) => typeof x === 'string')
                        .map((x: string) => x.trim())
                        .filter((x: string) => x.length > 0)
                    : [],
                  allergens: Array.isArray(m.allergens)
                    ? m.allergens
                        .filter(
                          (x: unknown) =>
                            typeof x === 'string' &&
                            validAllergens.has(x.trim()),
                        )
                        .map((x: string) => x.trim())
                    : [],
                }))
                .filter((m: GeminiGeneratedMenu) => m.name.length > 0 && m.price > 0)
            : [];

          return {
            name: String(r.name ?? '').trim(),
            category: String(r.category ?? '기타').trim(),
            priceRange: Math.max(1, Math.min(5, Math.floor(Number(r.priceRange) || 2))),
            addressHint: String(r.addressHint ?? '').trim(),
            menus,
          };
        })
        .filter((r) => r.name.length > 0 && r.menus.length > 0);
    } catch {
      this.logger.warn('GEMINI_RESTAURANT_RESPONSE_PARSE_FAILED');
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
    } catch {
      this.logger.warn('GEMINI_MENU_RESPONSE_PARSE_FAILED');
      return [];
    }
  }
}
