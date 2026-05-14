import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../supabase/supabase.service';
import { GeminiService } from '../gemini/gemini.service';
import { pickMenusForCategory } from './menu-library';
import { ensureRestaurantImageUrl } from '../restaurants/restaurant-image-fallback';

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

    // ── 카카오 0개 폴백 (2026-05-12 추가) ────────────────
    // 카카오 API 가 차단/오지/오류로 0개를 반환하면 그 좌표 동네에
    // Gemini 가 가상 식당 5개를 만들어 DB에 박는다. 빈 화면 방지 안전망.
    // 일반 도심에서는 거의 발동하지 않음 (카카오는 한국 거의 어디서나 식당 30개 반환).
    if (kakaoPlaces.length === 0) {
      this.logger.warn(
        '카카오 0개 반환 — Gemini 가상 식당 폴백 시도',
      );
      return this.fallbackGenerateVirtualRestaurants(lat, lng);
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
                // ── 사장님 피드백 대응 (2026-05-14) ─────────────
                //   "메뉴넣으면서 이미지도 넣어달라니까"
                //   Gemini 폴백 메뉴는 자체 imageUrl 이 없으므로 Unsplash
                //   Source API 로 메뉴명 키워드 기반 음식 사진을 자동 매핑.
                //   - 한국 식당 위주이므로 "korean,food" 카테고리 강제
                //   - 메뉴명을 추가 키워드로 넣어 비빔밥/김치찌개 등 매칭
                //   - 404 시 Unsplash 가 기본 음식 사진으로 대체해 줌
                //   카테고리 라이브러리 폴백(pickMenusForCategory)은 이미
                //   Unsplash URL 내장이라 그대로 유지.
                imageUrl: `https://source.unsplash.com/400x300/?korean,food,${encodeURIComponent(m.name)}`,
                ingredients: m.ingredients,
                allergens: m.allergens,
                source: 'AI_GEMINI',
              })),
            };
          }
        }

        // ── 카테고리 라이브러리 폴백 (2026-05-12 영구 해결책) ──
        // 네이버 + Gemini 둘 다 실패해도 카테고리(한식/일식/...) 기반으로
        // 정적 라이브러리에서 메뉴 + Unsplash 사진 자동 매핑. 어디서 켜든
        // 모든 식당이 메뉴+가격+사진 갖춰서 시연 임팩트 유지.
        if (!detail || detail.menus.length === 0) {
          const category = this.mapCategory(place.category_name);
          const libMenus = pickMenusForCategory(category, 5);
          this.logger.log(
            `카테고리 라이브러리 폴백 (${place.place_name}, ${category}): ${libMenus.length}개`,
          );
          detail = {
            name: place.place_name,
            rating: detail?.rating ?? 0,
            reviewCount: detail?.reviewCount ?? 0,
            imageUrl: detail?.imageUrl,
            businessHours: detail?.businessHours,
            menus: libMenus.map((m) => ({
              name: m.name,
              price: m.price,
              description: m.description,
              imageUrl: m.imageUrl,
              ingredients: m.ingredients,
              allergens: m.allergens,
              source: 'AI_GEMINI', // DB ENUM 제약 — 추후 'LIBRARY' 추가 검토
            })),
          };
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
  //
  // 2026-05-14 사장님 버그 신고 대응 ('위치권한 켜놨는데 식당 안 찾아짐'):
  //   기존엔 KAKAO_REST_API_KEY 미설정 시 throw → NestJS 글로벌 필터가 500 응답으로
  //   변환 → 클라이언트의 fire-and-forget 호출은 어차피 무시하지만, 추후 동기 흐름
  //   (예: 동일 흐름에서 추천이 카운트되는 경우)에 빈 결과가 아닌 예외 폭주.
  //
  //   변경:
  //   - 키 누락 → throw 대신 빈 배열 반환 + warn 로그.
  //     상위 crawlAndSeed() 가 카카오 0개를 감지하면 곧바로 Gemini 가상 식당
  //     폴백 경로(`fallbackGenerateVirtualRestaurants`)로 들어가 빈 화면을 막는다.
  //   - 카카오 4xx (할당량/인증/지역 차단) → 기존처럼 break + 빈 배열로 폴백.
  //
  //   즉, AWS EC2 에 KAKAO_REST_API_KEY 가 누락된 채 배포돼도 Gemini 가 가상
  //   식당 5개를 생성해 좌표 주변에 박아준다 (Gemini 키만 있으면 동작).
  //   Gemini 키마저 없으면 빈 결과 반환 → 클라이언트가 "주변 식당이 없어요" 안내.
  private async searchKakaoPlaces(
    lat: number,
    lng: number,
    radius: number,
  ): Promise<KakaoPlace[]> {
    const apiKey = this.config.get<string>('KAKAO_REST_API_KEY');
    if (!apiKey) {
      // 환경변수 누락은 운영 사고이므로 warn 으로 즉시 가시화.
      // throw 대신 빈 배열을 돌려서 Gemini 폴백 트리거.
      this.logger.warn(
        'KAKAO_REST_API_KEY 미설정 — 카카오 검색 스킵, Gemini 가상 식당 폴백으로 위임',
      );
      return [];
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

      let res: Response;
      try {
        // 네트워크 단절/타임아웃 등 예외도 break + 빈 배열로 폴백.
        // 한 페이지 실패가 전체 흐름을 중단시키면 안 됨.
        res = await fetch(url.toString(), {
          headers: { Authorization: `KakaoAK ${apiKey}` },
        });
      } catch (e) {
        this.logger.error(
          `카카오 API 네트워크 예외 (page=${page}): ${(e as Error).message}`,
        );
        break;
      }

      if (!res.ok) {
        // 401/403 인증 만료, 429 할당량 초과, 5xx 카카오 장애 모두 동일 처리.
        // 응답 본문을 200자만 잘라 로그에 남겨 원인 추적 도움.
        const body = await res.text().catch(() => '');
        this.logger.error(
          `카카오 API 에러: ${res.status} ${res.statusText} body=${body.slice(0, 200)}`,
        );
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
    //
    // ── 평점(rating) 매핑 (2026-05-14 추가) ─────────────────
    //   사장님 피드백 "네이버나 구글로 식당 평점 조사한 거 맞아?" 대응.
    //   네이버 플레이스 reviewScore 를 fetchNaverPlaceDetail() 에서 이미
    //   parseFloat 으로 수집 중이지만(L322 근처) DB rating 컬럼이 없어
    //   버려지고 있었음. 마이그레이션 2026-05-14-add-rating-column.sql
    //   로 NUMERIC(2,1) 컬럼이 생겼고, 여기서 실제로 값을 박는다.
    //   - 네이버에서 못 가져온 경우(rating === 0 이거나 detail null) null 저장
    //   - 0 점은 의미가 없으므로 null 로 정규화(추천 가중치 계산 시 영향 회피)
    const ratingRaw = naverDetail?.rating ?? 0;

    // ── 식당 이미지 폴백 (2026-05-14 추가) ───────────────────
    //   사장님 피드백 "메뉴넣으면서 이미지도 넣어달라니까" 후속 조치.
    //   네이버 thumUrl 이 있으면 그대로 쓰고, 없으면 카테고리·식당명 기반
    //   Unsplash Source API URL 로 자동 매핑. 빈 회색 박스 → 음식 사진.
    //   ensureRestaurantImageUrl 헬퍼는 시드/응답 매핑과 100% 동일한 규칙.
    const restaurantImageUrl = ensureRestaurantImageUrl(
      naverDetail?.imageUrl,
      category,
      kakaoPlace.place_name,
    );

    const restaurantData = {
      name: kakaoPlace.place_name,
      category,
      address: kakaoPlace.road_address_name || kakaoPlace.address_name,
      lat: parseFloat(kakaoPlace.y),
      lng: parseFloat(kakaoPlace.x),
      price_range: priceRange,
      rating: ratingRaw > 0 ? ratingRaw : null,
      image_url: restaurantImageUrl,
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

  // ══════════════════════════════════════════════════════
  // Gemini 가상 식당 폴백 (2026-05-12 추가)
  // ══════════════════════════════════════════════════════
  // 카카오가 0개를 반환한 좌표에 대해 Gemini 가 가상 식당 5개 + 메뉴를 생성하고
  // 좌표 주변에 흩뿌려 DB에 저장한다.
  //
  // 흩뿌리기:
  //   각 식당을 호출 좌표 ±0.003도(약 ±300m) 안에 무작위 배치.
  //   추천 화면에서 거리 필터(반경 1km)에 모두 잡히도록 충분히 가깝게.
  //
  // 중복 방지:
  //   saveToDb 와 동일하게 (name, address) 중복 체크. Gemini 가 같은 이름을
  //   다시 만들어도 INSERT 안 되고 UPDATE 만 일어남 → 데이터 폭증 방지.
  private async fallbackGenerateVirtualRestaurants(
    lat: number,
    lng: number,
  ): Promise<CrawlResult> {
    // 좌표 → 동네 힌트 변환은 역지오코딩이 필요한데, 추가 API 의존을 피하기 위해
    // 일단 좌표 자체를 areaHint 에 흘려보냄. Gemini 가 그럭저럭 맞는 가상 주소를
    // 생성해 줌. (정확도가 필요해지면 카카오 좌표→주소 변환 API 추가 가능)
    const areaHint = `위도 ${lat.toFixed(4)}, 경도 ${lng.toFixed(4)} 근처`;

    const generated = await this.gemini.generateRestaurantsForArea({
      areaHint,
      count: 5,
      categories: ['한식', '분식', '일식', '양식', '중식'],
    });

    if (generated.length === 0) {
      this.logger.warn('Gemini 폴백도 0개 — 완전 빈 결과 반환');
      return {
        totalSearched: 0,
        totalSaved: 0,
        totalMenus: 0,
        restaurants: [],
      };
    }

    const client = this.supabase.client;
    const results: Array<{ name: string; menuCount: number }> = [];
    let totalMenus = 0;
    let totalSaved = 0;

    for (const r of generated) {
      try {
        // 좌표 ±0.003도(약 ±300m) 안에 흩뿌림 — 반경 1km 추천에 충분히 잡힘
        const jitterLat = lat + (Math.random() - 0.5) * 0.006;
        const jitterLng = lng + (Math.random() - 0.5) * 0.006;

        // Gemini 가상 식당도 image_url 폴백 동일 적용 (2026-05-14).
        // 가상 식당은 자체 사진이 없으므로 무조건 카테고리·이름 매핑 URL.
        const restaurantData = {
          name: r.name,
          category: r.category,
          address: r.addressHint || areaHint,
          lat: jitterLat,
          lng: jitterLng,
          price_range: r.priceRange,
          image_url: ensureRestaurantImageUrl(null, r.category, r.name),
        };

        // 중복 체크 (이름 + 주소)
        const { data: existing } = await client
          .from('restaurants')
          .select('id')
          .eq('name', restaurantData.name)
          .eq('address', restaurantData.address)
          .limit(1);

        let restaurantId: string;
        if (existing && existing.length > 0) {
          restaurantId = existing[0].id;
          await client
            .from('restaurants')
            .update(restaurantData)
            .eq('id', restaurantId);
        } else {
          const { data: inserted, error } = await client
            .from('restaurants')
            .insert(restaurantData)
            .select('id')
            .single();
          if (error || !inserted) {
            this.logger.error(
              `Gemini 가상식당 저장 실패 (${r.name}): ${error?.message}`,
            );
            continue;
          }
          restaurantId = inserted.id;
        }

        // 메뉴 저장 (기존 메뉴 정리 후 재삽입)
        await client
          .from('menu_items')
          .delete()
          .eq('restaurant_id', restaurantId);

        const menuRows = r.menus.map((m) => ({
          restaurant_id: restaurantId,
          name: m.name,
          price: m.price,
          category: m.category,
          description: '', // Gemini 는 설명 미생성
          // ── 사장님 피드백 대응 (2026-05-14) ─────────────────
          //   가상 식당 폴백 경로에서도 메뉴 이미지를 자동 매핑.
          //   Unsplash Source API + 메뉴명 키워드로 음식 사진을 채워줘
          //   "메뉴는 있는데 사진은 비어있다" 시연 임팩트 손실을 막는다.
          image_url: `https://source.unsplash.com/400x300/?korean,food,${encodeURIComponent(m.name)}`,
          ingredients: m.ingredients,
          allergens: m.allergens,
          source: 'AI_GEMINI',
        }));

        const { error: menuError } = await client
          .from('menu_items')
          .insert(menuRows);

        if (menuError) {
          this.logger.warn(
            `Gemini 가상메뉴 저장 실패 (${r.name}): ${menuError.message}`,
          );
          continue;
        }

        totalMenus += r.menus.length;
        totalSaved++;
        results.push({ name: r.name, menuCount: r.menus.length });
        this.logger.log(
          `Gemini 가상식당 저장: ${r.name} (메뉴 ${r.menus.length}개)`,
        );
      } catch (e) {
        this.logger.warn(`Gemini 가상식당 처리 예외 (${r.name}): ${e}`);
      }
    }

    this.logger.log(
      `Gemini 폴백 완료: ${totalSaved}개 식당, ${totalMenus}개 메뉴 저장`,
    );

    return {
      totalSearched: generated.length,
      totalSaved,
      totalMenus,
      restaurants: results,
    };
  }
}
