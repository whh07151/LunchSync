import { INestApplication, ValidationPipe } from '@nestjs/common';
import { GUARDS_METADATA } from '@nestjs/common/constants';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';

describe('AuthController phone verification boundaries', () => {
  const phoneResult = { accessToken: 'token' };
  let service: {
    phoneVerify: jest.Mock;
    attachVerifiedPhone: jest.Mock;
  };
  let controller: AuthController;

  beforeEach(() => {
    service = {
      phoneVerify: jest.fn().mockResolvedValue(phoneResult),
      attachVerifiedPhone: jest.fn().mockResolvedValue(phoneResult),
    };
    controller = new AuthController(service as unknown as AuthService);
  });

  it('derives public phone login only from the verified Firebase token', async () => {
    await controller.verifyPhone({ idToken: 'firebase-token' });

    expect(service.phoneVerify).toHaveBeenCalledWith('firebase-token');
    expect(service.attachVerifiedPhone).not.toHaveBeenCalled();
  });

  it('derives the account-link target from the authenticated JWT principal', async () => {
    await controller.attachPhone(
      { user: { type: 'USER', userId: 'authenticated-user' } },
      { idToken: 'firebase-token' },
    );

    expect(service.attachVerifiedPhone).toHaveBeenCalledWith(
      'firebase-token',
      'authenticated-user',
    );
  });

  it('protects the account-link endpoint with JwtAuthGuard', () => {
    const guards = Reflect.getMetadata(
      GUARDS_METADATA,
      AuthController.prototype.attachPhone,
    ) as unknown[];

    expect(guards).toContain(JwtAuthGuard);
  });
});

describe('AuthController phone verification HTTP boundary', () => {
  let app: INestApplication;
  const service = {
    phoneVerify: jest.fn(),
    attachVerifiedPhone: jest.fn(),
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [AuthController],
      providers: [{ provide: AuthService, useValue: service }],
    }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('rejects a caller-supplied account target before invoking phone auth', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/auth/verify-phone')
      .send({
        idToken: 'firebase-token',
        existingUserId: 'victim-user-id',
      });

    expect(response.status).toBe(400);
    expect(service.phoneVerify).not.toHaveBeenCalled();
    expect(service.attachVerifiedPhone).not.toHaveBeenCalled();
  });
});
