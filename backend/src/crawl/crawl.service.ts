import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface KakaoPlace {
  id: string;
  place_name: string;
  category_name: string;
  road_address_name: string;
  address_name: string;
  x: string;
  y: string;
  distance: string;
}

export interface NearbyPlace {
  id: string;
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  kakaoUrl: string;
  distanceMeters: number;
  source: 'KAKAO';
}

/** Kakao Local을 조회해 일회성 장소 결과만 반환한다. 메뉴와 DB는 수정하지 않는다. */
@Injectable()
export class CrawlService {
  private readonly recent = new Map<string, { expiresAt: number; places: NearbyPlace[] }>();
  constructor(private readonly config: ConfigService) {}

  async discoverNearby(lat: number, lng: number, radiusMeters = 1000): Promise<NearbyPlace[]> {
    const apiKey = this.config.get<string>('KAKAO_REST_API_KEY');
    if (!apiKey) {
      throw new ServiceUnavailableException('주변 장소 검색 설정이 필요합니다.');
    }
    const cacheKey = `${lat.toFixed(5)}:${lng.toFixed(5)}:${radiusMeters}`;
    const cached = this.recent.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) return cached.places;

    const places: NearbyPlace[] = [];
    const seen = new Set<string>();
    for (let page = 1; page <= 3; page++) {
      const url = new URL('https://dapi.kakao.com/v2/local/search/category.json');
      url.searchParams.set('category_group_code', 'FD6');
      url.searchParams.set('x', String(lng));
      url.searchParams.set('y', String(lat));
      url.searchParams.set('radius', String(radiusMeters));
      url.searchParams.set('sort', 'distance');
      url.searchParams.set('size', '15');
      url.searchParams.set('page', String(page));

      let response: Response;
      try {
        response = await fetch(url, {
          headers: { Authorization: `KakaoAK ${apiKey}` },
          signal: AbortSignal.timeout(5000),
        });
      } catch {
        throw new ServiceUnavailableException('카카오 장소 검색에 연결할 수 없습니다.');
      }
      if (!response.ok) {
        throw new ServiceUnavailableException('카카오 장소 검색이 응답하지 않았습니다.');
      }

      let body: { documents?: KakaoPlace[]; meta?: { is_end?: boolean } };
      try {
        body = await response.json();
      } catch {
        throw new ServiceUnavailableException('카카오 장소 검색 응답을 읽을 수 없습니다.');
      }
      if (!Array.isArray(body.documents)) {
        throw new ServiceUnavailableException('카카오 장소 검색 응답 형식이 올바르지 않습니다.');
      }

      for (const place of body.documents) {
        const placeLat = Number(place.y);
        const placeLng = Number(place.x);
        const distanceMeters = Number(place.distance);
        if (!/^\d+$/.test(place.id) || seen.has(place.id) ||
            !Number.isFinite(placeLat) || !Number.isFinite(placeLng) ||
            !Number.isFinite(distanceMeters) || distanceMeters < 0) continue;
        seen.add(place.id);
        places.push({
          id: place.id,
          name: place.place_name,
          category: mapCategory(place.category_name),
          address: place.road_address_name || place.address_name,
          lat: placeLat,
          lng: placeLng,
          kakaoUrl: `https://place.map.kakao.com/${place.id}`,
          distanceMeters,
          source: 'KAKAO',
        });
      }
      if (body.meta?.is_end) break;
    }
    const sorted = places.sort((a, b) => a.distanceMeters - b.distanceMeters);
    if (this.recent.size >= 100) this.recent.clear();
    this.recent.set(cacheKey, { expiresAt: Date.now() + 60_000, places: sorted });
    return sorted;
  }
}

function mapCategory(value: string): string {
  if (value.includes('한식')) return '한식';
  if (value.includes('중식')) return '중식';
  if (value.includes('일식')) return '일식';
  if (value.includes('양식')) return '양식';
  if (value.includes('분식')) return '분식';
  return '음식점';
}
