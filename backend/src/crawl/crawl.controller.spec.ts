import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CrawlController } from './crawl.controller';
import { CrawlService } from './crawl.service';

describe('nearby discovery HTTP contract', () => {
  let app: INestApplication;
  const discoverNearby = jest.fn().mockResolvedValue([{
    id: '123', name: '가상 장소', category: '한식', address: '가상로 1',
    lat: 37.5665, lng: 126.978, kakaoUrl: 'https://place.map.kakao.com/123',
    distanceMeters: 40, source: 'KAKAO',
  }]);

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [CrawlController],
      providers: [{ provide: CrawlService, useValue: { discoverNearby } }],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();
    app = module.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
    await app.init();
  });

  afterAll(async () => app.close());
  beforeEach(() => discoverNearby.mockClear());

  it('returns 200 and the list expected by Flutter', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/crawl/nearby')
      .send({ lat: 37.5665, lng: 126.978, radius: 1000 });
    expect(response.status).toBe(200);
    expect(response.body.data[0]).toMatchObject({ id: '123', source: 'KAKAO' });
    expect(discoverNearby).toHaveBeenCalledWith(37.5665, 126.978, 1000);
  });

  it('rejects invalid radius before provider calls', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/crawl/nearby')
      .send({ lat: 37.5665, lng: 126.978, radius: 6000 });
    expect(response.status).toBe(400);
    expect(discoverNearby).not.toHaveBeenCalled();
  });

  it('keeps legacy POST read-only for older clients', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/crawl/restaurants')
      .send({ lat: 37.5665, lng: 126.978, radius: 1000 });
    expect(response.status).toBe(201);
    expect(response.body.data).toMatchObject({ totalSearched: 1, totalSaved: 0, totalMenus: 0 });
  });
});
