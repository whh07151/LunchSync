import { ConfigService } from '@nestjs/config';
import { CrawlService } from './crawl.service';

describe('CrawlService read-only nearby discovery', () => {
  afterEach(() => jest.restoreAllMocks());

  it('returns 45 synthetic Kakao places in distance order without touching the database', async () => {
    const fetchMock = jest.spyOn(global, 'fetch').mockImplementation(async (input) => {
      const page = Number(new URL(String(input)).searchParams.get('page'));
      return {
        ok: true,
        json: async () => ({
          meta: { is_end: page === 3 },
          documents: Array.from({ length: 15 }, (_, index) => {
            const id = (page - 1) * 15 + index + 1;
            return {
              id: String(id), place_name: `가상 식당 ${id}`,
              category_name: '음식점 > 한식',
              road_address_name: `가상로 ${id}`, address_name: '',
              x: '126.978', y: '37.5665', distance: String(1000 - id),
            };
          }),
        }),
      } as Response;
    });
    const service = new CrawlService(
      { get: () => 'fake-key' } as unknown as ConfigService,
    );

    const places = await service.discoverNearby(37.5665, 126.978, 1000);

    expect(places).toHaveLength(45);
    expect(places[0]).toMatchObject({ id: '45', source: 'KAKAO', distanceMeters: 955 });
    expect(places[0].kakaoUrl).toBe('https://place.map.kakao.com/45');
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it('reports missing API configuration rather than inventing local restaurants', async () => {
    const service = new CrawlService(
      { get: () => undefined } as unknown as ConfigService,
    );
    await expect(service.discoverNearby(37.5665, 126.978)).rejects.toThrow();
  });
});
