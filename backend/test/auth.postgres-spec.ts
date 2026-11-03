import { resolve } from 'node:path';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import { Pool } from 'pg';
import request from 'supertest';
import { AuthController } from '../src/auth/auth.controller';
import { AuthService } from '../src/auth/auth.service';
import { FirebaseService } from '../src/auth/firebase.service';
import { SupabaseService } from '../src/supabase/supabase.service';
import { DisposablePostgres } from './support/disposable-postgres';

// This adapter exercises real PostgreSQL persistence/unique constraints while
// keeping OAuth synthetic and never connecting to the user's Supabase project.
class AuthPostgresClient {
  private gatedReads = 0;
  private releaseReads: (() => void) | undefined;
  private gate: Promise<void> | undefined;
  constructor(private readonly pool: Pool) {}
  gateTwoInitialReads() {
    this.gatedReads = 0;
    this.gate = new Promise<void>((resolveGate) => {
      this.releaseReads = resolveGate;
    });
  }
  clearGate() {
    this.gate = undefined;
    this.releaseReads = undefined;
  }
  from(table: string) {
    if (table !== 'users') throw new Error('Unexpected table');
    let kakaoId: unknown;
    let payload: Record<string, unknown> | undefined;
    const execute = async () => {
      try {
        if (payload) {
          const result = await this.pool.query(
            `INSERT INTO public.users (kakao_id, name, profile_image, role, status, auth_provider, radius)
             VALUES ($1,$2,$3,$4,$5,$6,$7)
             RETURNING id,name,profile_image,org,budget,speed,role,status`,
            [
              payload.kakao_id,
              payload.name,
              payload.profile_image,
              payload.role,
              payload.status,
              payload.auth_provider,
              payload.radius,
            ],
          );
          return { data: result.rows[0], error: null };
        }
        const result = await this.pool.query(
          `SELECT id,name,profile_image,org,budget,speed,role,status FROM public.users WHERE kakao_id=$1`,
          [kakaoId],
        );
        if (this.gate && this.gatedReads < 2) {
          this.gatedReads += 1;
          if (this.gatedReads === 2) this.releaseReads?.();
          await this.gate;
        }
        return { data: result.rows[0] ?? null, error: null };
      } catch (error) {
        return {
          data: null,
          error: {
            code: (error as { code?: string }).code,
            message: 'synthetic DB error',
          },
        };
      }
    };
    const builder = {
      select: (_columns: string) => builder,
      eq: (column: string, value: unknown) => {
        if (column !== 'kakao_id')
          throw new Error('Unexpected identity filter');
        kakaoId = value;
        return builder;
      },
      insert: (value: Record<string, unknown>) => {
        payload = value;
        return builder;
      },
      maybeSingle: execute,
      single: execute,
    };
    return builder;
  }
}

describe('Kakao HTTP signup/login against disposable PostgreSQL', () => {
  jest.setTimeout(120000);
  let db: DisposablePostgres;
  let client: AuthPostgresClient;
  let app: INestApplication;
  let jwt: JwtService;
  let fetchMock: jest.SpiedFunction<typeof fetch>;
  const providerId = 123456;

  beforeAll(async () => {
    db = await DisposablePostgres.start(
      resolve(
        process.cwd(),
        'scripts/migrations/2026-07-27-create-order-with-items-v2.sql',
      ),
    );
    await db.pool.query(`
      ALTER TABLE public.users ALTER COLUMN id SET DEFAULT gen_random_uuid();
      ALTER TABLE public.users ADD COLUMN kakao_id TEXT UNIQUE;
      ALTER TABLE public.users ADD COLUMN name TEXT NOT NULL DEFAULT '가상 사용자';
      ALTER TABLE public.users ADD COLUMN profile_image TEXT;
      ALTER TABLE public.users ADD COLUMN org TEXT;
      ALTER TABLE public.users ADD COLUMN budget INT;
      ALTER TABLE public.users ADD COLUMN speed TEXT;
      ALTER TABLE public.users ADD COLUMN status TEXT NOT NULL DEFAULT 'APPROVED';
      ALTER TABLE public.users ADD COLUMN auth_provider TEXT;
      ALTER TABLE public.users ADD COLUMN radius TEXT;
    `);
    client = new AuthPostgresClient(db.pool);
    jwt = new JwtService({
      secret: 'synthetic-only-test-secret-not-for-production',
      signOptions: { expiresIn: '5m' },
    });
    const auth = new AuthService(
      { client } as unknown as SupabaseService,
      jwt,
      {} as FirebaseService,
      new ConfigService({ KAKAO_APP_ID: '1534395' }),
    );
    const module = await Test.createTestingModule({
      controllers: [AuthController],
      providers: [{ provide: AuthService, useValue: auth }],
    }).compile();
    app = module.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
    );
    await app.init();
  });
  beforeEach(() => {
    fetchMock = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(
        async (url) =>
          new Response(
            JSON.stringify(
              String(url).endsWith('access_token_info')
                ? { app_id: 1534395, id: providerId, expires_in: 3600 }
                : {
                    id: providerId,
                    kakao_account: { profile: { nickname: '가상 계정' } },
                  },
            ),
          ),
      );
  });
  afterEach(async () => {
    jest.restoreAllMocks();
    client.clearGate();
    await db.pool.query('TRUNCATE public.users CASCADE');
  });
  afterAll(async () => {
    await app?.close();
    await db?.stop();
  });

  it('persists signup, then restores the same account and completed onboarding on login', async () => {
    const first = await request(app.getHttpServer())
      .post('/api/auth/kakao')
      .send({ kakaoAccessToken: 'synthetic-token' })
      .expect(201);
    const initial = first.body.data;
    expect(first.body.success).toBe(true);
    expect(initial).toMatchObject({
      isNewUser: true,
      nextStep: 'PROFILE_SETUP',
    });
    expect(jwt.verify(initial.accessToken).sub).toBe(initial.user.id);
    await db.pool.query(
      'UPDATE public.users SET org=$1,budget=$2,speed=$3 WHERE id=$4',
      ['가상팀', 12000, 'NORMAL', initial.user.id],
    );
    const again = await request(app.getHttpServer())
      .post('/api/auth/kakao')
      .send({ kakaoAccessToken: 'synthetic-token' })
      .expect(201);
    expect(again.body.data).toMatchObject({
      isNewUser: false,
      nextStep: 'HOME',
      user: { id: initial.user.id },
    });
    expect(jwt.verify(again.body.data.accessToken).sub).toBe(initial.user.id);
    expect(
      (await db.pool.query('SELECT count(*)::int AS count FROM public.users'))
        .rows[0].count,
    ).toBe(1);
  });

  it('returns one persisted identity for two simultaneous first logins', async () => {
    client.gateTwoInitialReads();
    const results = await Promise.all(
      [0, 1].map(() =>
        request(app.getHttpServer())
          .post('/api/auth/kakao')
          .send({ kakaoAccessToken: 'synthetic-token' })
          .expect(201),
      ),
    );
    expect(results[0].body.data.user.id).toBe(results[1].body.data.user.id);
    expect(results.map((r) => r.body.data.isNewUser).sort()).toEqual([
      false,
      true,
    ]);
    expect(
      (await db.pool.query('SELECT count(*)::int AS count FROM public.users'))
        .rows[0].count,
    ).toBe(1);
  });

  it('returns 503 without issuing a JWT when a real schema lookup fails', async () => {
    const sign = jest.spyOn(jwt, 'sign');
    await db.pool.query(
      'ALTER TABLE public.users RENAME COLUMN kakao_id TO broken_kakao_id',
    );
    try {
      const result = await request(app.getHttpServer())
        .post('/api/auth/kakao')
        .send({ kakaoAccessToken: 'synthetic-token' })
        .expect(503);
      expect(result.body.code).toBe('KAKAO_ACCOUNT_LOOKUP_FAILED');
      expect(sign).not.toHaveBeenCalled();
      expect(
        (await db.pool.query('SELECT count(*)::int AS count FROM public.users'))
          .rows[0].count,
      ).toBe(0);
    } finally {
      await db.pool.query(
        'ALTER TABLE public.users RENAME COLUMN broken_kakao_id TO kakao_id',
      );
    }
  });

  it('rejects another app token and malformed requests before database insertion', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(
        JSON.stringify({ app_id: 999999, id: providerId, expires_in: 3600 }),
      ),
    );
    await request(app.getHttpServer())
      .post('/api/auth/kakao')
      .send({ kakaoAccessToken: 'synthetic-token' })
      .expect(401);
    await request(app.getHttpServer())
      .post('/api/auth/kakao')
      .send({})
      .expect(400);
    expect(
      (await db.pool.query('SELECT count(*)::int AS count FROM public.users'))
        .rows[0].count,
    ).toBe(0);
  });
});
