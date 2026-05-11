import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';
import { GeminiService } from '../gemini/gemini.service';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당 크롤링 서비스
//
// 3단 조합:
//   1. 카카오 로컬 API — GPS 좌표 + 반경으로 식당 목록 검색
//   2. 네이버 플레이스 비공식 API — 메뉴/가격/평점 상세 수집
//   3. Supabase DB — restaurants + menu_items 테이블에 저장
//
// 사용 시나리오:
//   POST /api/crawl/restaurants { lat, lng, radius }
//   → 카카오에서 식당 목록 → 네이버에서 상세 보강 → DB 저장
// ══════════════════════════════════════════════════════════

interface KakaoPlace {
  id: string;
  place_name: string;
  category_name: string;
  phone: string;
  address_name: string;
  road_address_name: string;
  x: string; // 경도
  y: string; // 위도
  place_url: string;
  distance: string;
}

interface NaverMenuItem {
  name: string;
  price: number;
  description: string;
  imageUrl?: string | null;
  // Gemini AI 폴백 시 추가되는 알레르기/재료 메타 (옵션)
  ingredients?: string[];
  allergens?: string[];
  source?: 'CRAWL_NAVER' | 'AI_GEMINI' | 'MANUAL';
}

interface NaverPlaceDetail {
  name: string;
  rating: number;
  reviewCount: number;
  menus: NaverMenuItem[];
  businessHours?: string;
  imageUrl?: string;
}

export interface CrawlResult {
  totalSearched: number;
  totalSaved: number;
  totalMenus: number;
  restaurants: Array<{ name: string; menuCount: number }>;
}

@Injectable()
export class CrawlService {
  private readonly logger = new Logger(CrawlService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly supabase: SupabaseService,
    private readonly gemini: GeminiService,
  ) {}

  // ── 메인: 좌표 + 반경으로 식당 크롤링 → DB 저장 ──────────
  async crawlAndSeed(
    lat: number,
    lng: number,
    radiusMeters: number = 1000,
  ): Promise<CrawlResult> {
    this.logger.log(
      `크롤링 시작: 위도=${lat}, 경도=${lng}, 반경=${radiusMeters}m`,
    );

    // 1단계: 카카오 로컬 API로 식당 목록 검색
    const kakaoPlaces = await this.searchKakaoPlaces(lat, lng, radiusMeters);
    this.logger.log(`카카오 검색 결과: ${kakaoPlaces.length}개 식당`);

    if (kakaoPlaces.length === 0) {
      return {
        totalSearched: 0,
        totalSaved: 0,
        totalMenus: 0,
        restaurants: [],
      };
    }

    // 2단계: 각 식당에 대해 네이버에서 상세 정보 보강
    const results: Array<{ name: string; menuCount: number }> = [];
    let totalMenus = 0;
    let totalSaved = 0;

    for (const place of kakaoPlaces) {
      try {
        // 네이버에서 메뉴/가격/평점 수집
        let detail = await this.fetchNaverPlaceDetail(place.place_name);

        // 딜레이: 네이버 서버 부하 방지 (1초)
        await this.delay(1000);

        // ── Gemini 폴백 (2026-05-12) ─────────────────────
        // 네이버가 응답 안 했거나 메뉴 0개면 Gemini AI 로 메뉴 추정 생성.
        // source='AI_GEMINI' 로 표시해 사장이 추후 수정 가능.
        if (!detail || detail.menus.length === 0) {
          const aiMenus = await this.gemini.generateMenuForRestaurant({
            name: place.place_name,
            category: place.category_name,
          });
          if (aiMenus.length > 0) {
            this.logger.log(
              `Gemini AI 메뉴 폴백 (${place.place_name}): ${aiMenus.length}개`,
            );
            detail = {
              name: place.place_name,
              rating: detail?.rating ?? 0,
              reviewCount: detail?.reviewCount ?? 0,
              imageUrl: detail?.imageUrl,
              businessHours: detail?.businessHours,
              menus: aiMenus.map((m) => ({
                name: m.name,
                price: m.price,
                description: '', // Gemini 는 설명은 안 받음 (재료 위주)
                imageUrl: null,
                ingredients: m.ingredients,
                allergens: m.allergens,
                source: 'AI_GEMINI',
              })),
            };
          }
        }

        // 3단계: DB에 저장
        const menuCount = await this.saveToDb(place, detail);
        totalMenus += menuCount;
        totalSaved++;

        results.push({ name: place.place_name, menuCount });
        this.logger.log(
          `저장 완료: ${place.place_name} (메뉴 ${menuCount}개)`,
        );
      } catch (e) {
        this.logger.warn(`${place.place_name} 처리 실패: ${e}`);
      }
    }

    const result: CrawlResult = {
      totalSearched: kakaoPlaces.length,
      totalSaved,
      totalMenus,
      restaurants: results,
    };

    this.logger.log(
      `크롤링 완료: ${totalSaved}개 식당, ${totalMenus}개 메뉴 저장`,
    );
    return result;
  }

  // ── 1단계: 카카오 로컬 API 호출 ──────────────────────────
  // 카테고리 FD6 = 음식점
  // 반경 내 최대 45개 (페이지당 15개 × 3페이지)
  private async searchKakaoPlaces(
    lat: number,
    lng: number,
    radius: number,
  ): Promise<KakaoPlace[]> {
    const apiKey = this.config.get<string>('KAKAO_REST_API_KEY');
    if (!apiKey) {
      throw new Error('KAKAO_REST_API_KEY가 .env에 설정되지 않았습니다.');
    }

    const allPlaces: KakaoPlace[] = [];

    // 카카오 API는 페이지당 최대 15개, 최대 3페이지
    for (let page = 1; page <= 3; page++) {
      const url = new URL(
        'https://dapi.kakao.com/v2/local/search/category.json',
      );
      url.searchParams.set('category_group_code', 'FD6'); // 음식점
      url.searchParams.set('x', lng.toString());
      url.searchParams.set('y', lat.toString());
      url.searchParams.set('radius', radius.toString());
      url.searchParams.set('sort', 'distance');
      url.searchParams.set('size', '15');
      url.searchParams.set('page', page.toString());

      const res = await fetch(url.toString(), {
        headers: { Authorization: `KakaoAK ${apiKey}` },
      });

      if (!res.ok) {
        this.logger.error(`카카오 API 에러: ${res.status} ${res.statusText}`);
        break;
      }

      const data = await res.json();
      const documents: KakaoPlace[] = data.documents || [];
      allPlaces.push(...documents);

      // 마지막 페이지면 종료
      if (data.meta?.is_end) break;
    }

    return allPlaces;
  }

  // ── 2단계: 네이버 플레이스 비공식 API로 상세 수집 ─────────
  // 식당 이름으로 검색 → 첫 번째 결과의 메뉴/가격/평점 가져오기
  private async fetchNaverPlaceDetail(
    placeName: string,
  ): Promise<NaverPlaceDetail | null> {
    try {
      // 네이버 지도 검색 API (비공식)
      const searchUrl = `https://map.naver.com/p/api/search/allSearch?query=${encodeURIComponent(placeName)}&type=all`;

      const searchRes = await fetch(searchUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          Referer: 'https://map.naver.com/',
        },
      });

      if (!searchRes.ok) return null;

      const searchData = await searchRes.json();
      const placeList = searchData?.result?.place?.list;
      if (!placeList || placeList.length === 0) return null;

      const firstPlace = placeList[0];
      const placeId = firstPlace.id;

      // 메뉴 상세 조회 (비공식 API)
      const menuUrl = `https://pcmap-api.place.naver.com/place/rest/restaurant/${placeId}/menu`;
      const menuRes = await fetch(menuUrl, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          Referer: 'https://pcmap.place.naver.com/',
        },
      });

      let menus: NaverMenuItem[] = [];
      if (menuRes.ok) {
        const menuData = await menuRes.json();
        const menuItems = menuData?.menus || menuData?.menuItems || [];
        menus = this.parseNaverMenus(menuItems);
      }

      return {
        name: firstPlace.name || placeName,
        rating: parseFloat(firstPlace.reviewScore) || 0,
        reviewCount: parseInt(firstPlace.reviewCount) || 0,
        menus,
        businessHours: firstPlace.businessHours?.summary || null,
        imageUrl: firstPlace.thumUrl || firstPlace.imageUrl || null,
      };
    } catch (e) {
      this.logger.warn(`네이버 상세 조회 실패 (${placeName}): ${e}`);
      return null;
    }
  }

  // ── 네이버 메뉴 데이터 파싱 ──────────────────────────────
  private parseNaverMenus(menuItems: any[]): NaverMenuItem[] {
    if (!Array.isArray(menuItems)) return [];

    return menuItems
      .filter((item) => item.name && item.price)
      .map((item) => ({
        name: String(item.name).trim(),
        price: this.parsePrice(item.price),
        description: item.description || '',
        imageUrl: item.imageUrl || item.images?.[0] || null,
      }))
      .filter((item) => item.price > 0)
      .slice(0, 20); // 최대 20개 메뉴
  }

  // ── 가격 문자열 파싱 ("19,000원" → 19000) ───────────────
  private parsePrice(priceStr: any): number {
    if (typeof priceStr === 'number') return priceStr;
    if (typeof priceStr !== 'string') return 0;
    const cleaned = priceStr.replace(/[^0-9]/g, '');
    return parseInt(cleaned) || 0;
  }

  // ── 3단계: DB 저장 ────────────────────────────────────────
  private async saveToDb(
    kakaoPlace: KakaoPlace,
    naverDetail: NaverPlaceDetail | null,
  ): Promise<number> {
    const client = this.supabase.client;

    // 카테고리 매핑 (카카오 "음식점 > 한식" → "한식")
    const category = this.mapCategory(kakaoPlace.category_name);

    // 평균 가격대 계산
    const menus = naverDetail?.menus || [];
    const avgPrice =
      menus.length > 0
        ? Math.round(menus.reduce((s, m) => s + m.price, 0) / menus.length)
        : 0;
    const priceRange = avgPrice > 0 ? Math.round(avgPrice / 1000) : 2;

    // restaurants 테이블에 upsert
    const restaurantData = {
      name: kakaoPlace.place_name,
      category,
      address: kakaoPlace.road_address_name || kakaoPlace.address_name,
      lat: parseFloat(kakaoPlace.y),
      lng: parseFloat(kakaoPlace.x),
      price_range: priceRange,
    };

    // 이름+주소로 기존 데이터 확인
    const { data: existing } = await client
      .from('restaurants')
      .select('id')
      .eq('name', restaurantData.name)
      .eq('address', restaurantData.address)
      .limit(1);

    let restaurantId: string;

    if (existing && existing.length > 0) {
      restaurantId = existing[0].id;
      // 기존 데이터 업데이트
      await client
        .from('restaurants')
        .update(restaurantData)
        .eq('id', restaurantId);
    } else {
      // 새 데이터 삽입
      const { data: inserted, error } = await client
        .from('restaurants')
        .insert(restaurantData)
        .select('id')
        .single();

      if (error || !inserted) {
        this.logger.error(
          `식당 저장 실패 (${kakaoPlace.place_name}): ${error?.message}`,
        );
        return 0;
      }
      restaurantId = inserted.id;
    }

    // menu_items 테이블에 메뉴 저장
    if (menus.length > 0) {
      // 기존 메뉴 삭제 후 새로 삽입 (갱신 목적)
      await client
        .from('menu_items')
        .delete()
        .eq('restaurant_id', restaurantId);

      const menuRows = menus.map((m) => ({
        restaurant_id: restaurantId,
        name: m.name,
        price: m.price,
        category: this.mapMenuCategory(m.name),
        description: m.description,
        image_url: m.imageUrl || null,
        // Gemini AI 폴백 시 채워진 필드. 네이버 출처면 빈 배열.
        ingredients: m.ingredients ?? [],
        allergens: m.allergens ?? [],
        source: m.source ?? 'CRAWL_NAVER',
      }));

      const { error: menuError } = await client
        .from('menu_items')
        .insert(menuRows);

      if (menuError) {
        this.logger.warn(`메뉴 저장 실패: ${menuError.message}`);
        return 0;
      }
    }

    return menus.length;
  }

  // ── 카카오 카테고리 → DB 카테고리 매핑 ────────────────────
  private mapCategory(kakaoCategory: string): string {
    const cat = kakaoCategory.toLowerCase();
    if (cat.includes('한식')) return '한식';
    if (cat.includes('중식') || cat.includes('중국')) return '중식';
    if (cat.includes('일식') || cat.includes('일본')) return '일식';
    if (cat.includes('양식') || cat.includes('이탈리') || cat.includes('프랑스'))
      return '양식';
    if (cat.includes('분식')) return '분식';
    if (cat.includes('카페') || cat.includes('디저트')) return '카페';
    if (
      cat.includes('패스트') ||
      cat.includes('버거') ||
      cat.includes('치킨')
    )
      return '패스트푸드';
    if (cat.includes('아시안') || cat.includes('베트남') || cat.includes('태국'))
      return '아시안';
    return '기타';
  }

  // ── 메뉴명 → 메뉴 카테고리 추론 ──────────────────────────
  private mapMenuCategory(menuName: string): string {
    const name = menuName.toLowerCase();
    if (name.includes('밥') || name.includes('덮밥') || name.includes('비빔'))
      return 'rice';
    if (
      name.includes('면') ||
      name.includes('국수') ||
      name.includes('라멘') ||
      name.includes('파스타')
    )
      return 'noodle';
    if (
      name.includes('음료') ||
      name.includes('커피') ||
      name.includes('주스') ||
      name.includes('콜라')
    )
      return 'drink';
    if (
      name.includes('떡볶이') ||
      name.includes('튀김') ||
      name.includes('만두')
    )
      return 'snack';
    return 'main';
  }

  // ── 딜레이 유틸 ───────────────────────────────────────────
  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
