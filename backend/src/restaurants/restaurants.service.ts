import { BadRequestException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { normalizePriceRangeToWon } from './price-range-normalizer';

// ══════════════════════════════════════════════════════════
// 파일 역할: 식당/메뉴 비즈니스 로직
//
// 현재: 기본 CRUD + 예산/카테고리 필터링
// 추후: CORE-07(추천 엔진)에서 점수 기반 정렬 추가 예정
// ══════════════════════════════════════════════════════════

export interface GetRestaurantsQuery {
  category?: string;
  maxPrice?: number;
  limit?: number;
  offset?: number;
  // 위치 기반 필터 (2026-05-12 추가) — 사용자 GPS 좌표 + 반경(m).
  // lat/lng/radius 모두 제공 시 Haversine 으로 반경 내만 반환.
  lat?: number;
  lng?: number;
  radius?: number;
}

@Injectable()
export class RestaurantsService {
  constructor(private readonly supabase: SupabaseService) {}

  // ── GET /restaurants ──────────────────────────────────
  // 필터 조건으로 식당 목록 조회
  async getRestaurants(query: GetRestaurantsQuery) {
    if ((query.lat == null) !== (query.lng == null)) {
      throw new BadRequestException('위도와 경도를 함께 입력해 주세요.');
    }
    if (query.lat != null && (!Number.isFinite(query.lat) || Math.abs(query.lat) > 90 ||
        !Number.isFinite(query.lng) || Math.abs(query.lng!) > 180)) {
      throw new BadRequestException('유효한 위도와 경도를 입력해 주세요.');
    }
    if (query.radius != null && (!Number.isFinite(query.radius) || query.radius < 50 || query.radius > 5000)) {
      throw new BadRequestException('반경은 50~5000m로 입력해 주세요.');
    }
    if (query.limit != null && (!Number.isInteger(query.limit) || query.limit < 1 || query.limit > 100)) {
      throw new BadRequestException('조회 개수는 1~100개로 입력해 주세요.');
    }
    if (query.offset != null && (!Number.isInteger(query.offset) || query.offset < 0 || query.offset > 1000)) {
      throw new BadRequestException('시작 위치는 0~1000 사이여야 합니다.');
    }
    // 2026-05-13 image_url 컬럼 select 추가:
    //   클라이언트 RestaurantDto.imageUrl 매핑용. 사장님 피드백 "사진 잘 보였으면"
    //   대응. 카드/상세에서 사진 렌더링이 가능해짐 (없으면 FoodImage 폴백 동작).
    //
    // 2026-05-14 rating 컬럼 select 추가:
    //   사장님 피드백 "네이버나 구글로 식당 평점 조사한 거 맞아?" 대응.
    //   CrawlService 가 네이버 reviewScore 를 수집해 restaurants.rating 에 저장
    //   하게 됐으므로 클라이언트로도 함께 내려준다. UI 에서 "⭐ 4.2" 표기.
    // 2026-05-31 WOW#1 todays_note 컬럼 select 추가:
    //   사장이 POS/사장앱에서 입력한 "오늘의 한 줄" 메시지.
    //   응답 camelCase 키 todaysNote 로 변환되어 손님 추천 카드 노란 띠와
    //   추천 점수 가중치(+5)에 사용된다. NULL 이면 UI 에 노출되지 않음.
    const createQuery = () => {
      let qb = this.supabase.client
        .from('restaurants')
        .select('id, name, category, price_range, address, lat, lng, image_url, rating, todays_note, created_at');
      if (query.category) qb = qb.eq('category', query.category);
      if (query.maxPrice != null) qb = qb.lte('price_range', query.maxPrice);
      return qb;
    };

    let rows: any[];
    if (query.lat != null && query.lng != null) {
      const radius = query.radius ?? 1000;
      const latDelta = radius / 111_320;
      const lngDelta = radius / (111_320 * Math.max(0.01, Math.cos(query.lat * Math.PI / 180)));
      const candidates: any[] = [];
      // PostgREST의 기본 1000행 제한을 넘는 지역도 빠뜨리지 않도록 페이지별 조회.
      for (let start = 0; start <= 5000; start += 1000) {
        const { data, error } = await createQuery()
          .gte('lat', query.lat - latDelta)
          .lte('lat', query.lat + latDelta)
          .gte('lng', query.lng - lngDelta)
          .lte('lng', query.lng + lngDelta)
          .order('id')
          .range(start, start === 5000 ? start : start + 999);
        if (error) throw new Error('RESTAURANT_LIST_LOOKUP_FAILED');
        if (start === 5000 && (data ?? []).length > 0) {
          throw new ServiceUnavailableException('주변 식당 후보가 너무 많아 범위를 좁혀야 합니다.');
        }
        candidates.push(...(data ?? []));
        if ((data ?? []).length < 1000) break;
      }
      rows = candidates
        .map((r) => ({ row: r, distance: haversineMeters(query.lat!, query.lng!, Number(r.lat), Number(r.lng)) }))
        .filter(({ distance }) => distance <= radius)
        .sort((a, b) => a.distance - b.distance || String(a.row.id).localeCompare(String(b.row.id)))
        .slice(query.offset ?? 0, (query.offset ?? 0) + (query.limit ?? 20))
        .map(({ row }) => row);
    } else {
      let qb = createQuery().order('created_at', { ascending: false });
      if (query.offset != null) {
        qb = qb.range(query.offset, query.offset + (query.limit ?? 20) - 1);
      } else if (query.limit != null) {
        qb = qb.limit(query.limit);
      }
      const { data, error } = await qb;
      if (error) throw new Error('RESTAURANT_LIST_LOOKUP_FAILED');
      rows = data ?? [];
    }

    return rows.map((r: any) => ({
      id: r.id,
      name: r.name,
      category: r.category,
      priceRange: r.price_range,
      // 2026-05-14: price_range 출처(시드/크롤/Gemini)가 섞여 있어
      // 단위가 들쭉날쭉. 프론트가 매번 휴리스틱을 돌리지 않도록 백엔드가
      // 추정 원(₩) 단위 평균가를 동봉. null 이면 "가격 정보 없음" 의미.
      // 헬퍼: price-range-normalizer.ts (lib/core/utils/normalizer.dart 와 동기).
      estimatedPriceWon: normalizePriceRangeToWon(r.price_range),
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      // 2026-05-14: 응답 단 최후 방어층. 시드/크롤이 누락된 옛 레코드도
      // 카테고리·이름 기반 Unsplash URL 로 자동 채워서 내려보낸다.
      // (DB 마이그레이션이 적용되기 전 EC2 상태에서도 시연 안전.)
      imageUrl: displayableImageUrl(r.image_url),
      // 네이버 플레이스 평점 (0.0~5.0). 미수집 식당은 null.
      // 클라이언트 RestaurantDto.rating 에 매핑되어 ⭐ 칩으로 표시됨.
      rating: r.rating != null ? Number(r.rating) : null,
      // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄".
      //   null 이면 손님 카드에서 노란 띠 숨김. 비어있는 문자열도 동일 취급
      //   되도록 trim 후 길이 0 인 경우 명시적으로 null 로 normalize.
      todaysNote:
        typeof r.todays_note === 'string' && r.todays_note.trim().length > 0
          ? r.todays_note
          : null,
      createdAt: r.created_at,
    }));
  }

  // ── GET /restaurants/:id ──────────────────────────────
  async getRestaurantById(id: string) {
    // 2026-05-14 rating 컬럼 select 추가 — 상세 화면에서도 평점 표시.
    // 2026-05-31 todays_note 컬럼 select 추가 — 상세 화면 상단 노란 띠 노출용.
    const { data, error } = await this.supabase.client
      .from('restaurants')
      .select('id, name, category, price_range, address, lat, lng, image_url, rating, todays_note, created_at')
      .eq('id', id)
      .single();

    if (error || !data) {
      throw new NotFoundException('식당을 찾을 수 없습니다.');
    }

    // 2026-05-15: 사장님 발견 "식당 정보 표시 불안정" 회귀 안전망.
    // 모든 필드에 명시적 fallback — null/empty 시에도 화면이 빈 채로
    // 머물지 않게. ensureRestaurantImageUrl 은 이미 3층 안전망.
    return {
      id: data.id,
      name: data.name ?? '식당',
      category: data.category ?? '기타',
      priceRange: data.price_range,
      estimatedPriceWon: normalizePriceRangeToWon(data.price_range),
      address: data.address ?? '',
      lat: data.lat,
      lng: data.lng,
      imageUrl: displayableImageUrl(data.image_url),
      rating: data.rating != null ? Number(data.rating) : null,
      // 2026-05-31 WOW#1: 사장님 "오늘의 한 줄".
      //   목록 응답과 동일 정규화 규칙 적용 (빈 문자열 → null).
      todaysNote:
        typeof data.todays_note === 'string' &&
        data.todays_note.trim().length > 0
          ? data.todays_note
          : null,
      createdAt: data.created_at,
    };
  }

  // ── Haversine 거리 계산 ──────────────────────────────
  // 두 위경도 좌표 사이 지표면 거리(m). recommendations.service 와 동일 로직.
  // PostGIS 미사용 환경에서 서비스 단 임시 필터링 용도.
  // ── GET /restaurants/:id/menus ────────────────────────
  async getMenusByRestaurant(restaurantId: string) {
    const { data, error } = await this.supabase.client
      .from('menu_items')
      .select('id, name, price, category, description, image_url, source, is_available')
      .eq('restaurant_id', restaurantId)
      .eq('is_available', true)
      .order('category')
      .order('price');

    if (error) {
      throw new Error('RESTAURANT_MENU_LOOKUP_FAILED');
    }

    // 예시 검색 이미지를 실제 메뉴 사진처럼 반환하지 않는다.
    const menus = (data ?? []).map((m) => ({
      id: m.id,
      name: m.name ?? '메뉴',
      price: m.price ?? 0,
      category: m.category ?? '기타',
      description: m.description ?? '',
      imageUrl: m.source === 'MANUAL' ? displayableImageUrl(m.image_url) : null,
      source: m.source ?? 'UNKNOWN',
      priceVerifiedAt: null,
    }));

    // DTO 기준: { categories[], menus[] } 구조로 반환
    // categories: '전체' + 중복 제거된 카테고리 목록
    const uniqueCategories = [...new Set(menus.map((m) => m.category).filter(Boolean))];
    const categories = ['전체', ...uniqueCategories];

    return { categories, menus };
  }

  // ══════════════════════════════════════════════════════════
  // WOW#5 단골 랭킹 (2026-05-31 추가)
  // ══════════════════════════════════════════════════════════
  //
  // 핵심: 손님이 한 식당에 몇 번 픽업 완료했는지 카운트 → 등급(NORMAL/REGULAR/VIP) 결정.
  // 이 식당 상세 헤더 뱃지 + 픽업 완료 토스트 + 사장 측 VIP 알림에서 동시 사용.
  //
  // 카운트 기준 (성능):
  //   - orders 테이블에서 head: true + count: 'exact' 옵션으로 전체 ROW 페치 없이
  //     COUNT 만 받아옴. GROUP BY 가 필요한 게 아니라 단일 (user, restaurant) 카운트.
  //   - 인덱스: orders(user_id, restaurant_id, status) 합성 인덱스가 권장되지만
  //     기존 user_id/restaurant_id 개별 인덱스만으로도 일일 트래픽엔 충분.
  async getLoyalty(
    restaurantId: string,
    userId: string,
  ): Promise<{
    visitCount: number;
    rank: 'NORMAL' | 'REGULAR' | 'VIP';
    isFirstTime: boolean;
  }> {
    // count: 'exact' + head: true → 결과 행은 안 받고 카운트만.
    // 같은 식당에서 같은 손님의 COMPLETED 주문 개수 = 방문(픽업) 횟수.
    const { count, error } = await this.supabase.client
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('restaurant_id', restaurantId)
      .eq('status', 'COMPLETED');

    if (error) {
      throw new Error('RESTAURANT_LOYALTY_COUNT_LOOKUP_FAILED');
    }

    const visitCount = count ?? 0;
    return {
      visitCount,
      rank: resolveLoyaltyRank(visitCount),
      // isFirstTime 의 정의: "지금 이 방문이 첫 픽업인가?" 가 아니라
      // "이 식당과의 누적 방문이 1회인가" — 픽업 완료 직후 토스트의
      // "이번이 첫 방문이에요" 카피용. visitCount === 1 이면 true.
      isFirstTime: visitCount === 1,
    };
  }
}

function displayableImageUrl(value: unknown): string | null {
  if (typeof value !== 'string' || value.trim().length === 0) return null;
  // 과거 시드/AI 생성 결과는 검색 URL을 저장했다. 해당 식당/메뉴 사진이 아니다.
  if (value.includes('source.unsplash.com/')) return null;
  return value;
}

// ══════════════════════════════════════════════════════════
// 단골 등급 헬퍼 (다른 서비스에서도 재사용 가능하도록 export)
// ══════════════════════════════════════════════════════════
//
// 규칙(고정 — 프론트 뱃지 색과 1:1 대응):
//   0~2회 → NORMAL  (흰 배경 뱃지)
//   3~4회 → REGULAR (주황 뱃지)
//   5회~  → VIP     (금색 뱃지)
//
// pos.service.ts 의 알림 발송 로직(특정 회차 도달 시 ORDER_VIP 발송)에서도
// 사용. 단일 진입점 보장 — 프론트와 백엔드가 같은 임계값을 공유.
export function resolveLoyaltyRank(
  visitCount: number,
): 'NORMAL' | 'REGULAR' | 'VIP' {
  if (visitCount >= 5) return 'VIP';
  if (visitCount >= 3) return 'REGULAR';
  return 'NORMAL';
}

// ══════════════════════════════════════════════════════════
// 단골 알림 발송 정책 (2026-05-31 추가)
// ══════════════════════════════════════════════════════════
//
// pos.service.ts updateOrderStatus 가 COMPLETED 분기에서 호출.
// "매 5의 배수" 회차 도달 시 ORDER_VIP 알림(축하 톤).
//   - 5회: VIP 승급 (최초 VIP 도달)
//   - 10/15/20/...회: 누적 단골 축하 milestone
// 1~4회는 클라이언트 토스트로만 처리(서버 알림 X — 노이즈 방지).
export function shouldSendLoyaltyMilestone(visitCount: number): boolean {
  if (visitCount < 5) return false;
  return visitCount % 5 === 0;
}

// ── Haversine 거리 계산 (m) ─────────────────────────────
// recommendations.service.ts 동일 로직.
function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371000; // 지구 반지름 (m)
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}
