import { Test, TestingModule } from '@nestjs/testing';
import { HttpException } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { SchemaHealthcheckService } from './supabase/schema-healthcheck.service';

describe('AppController', () => {
  let appController: AppController;
  const schemaHealthcheck = {
    getReadinessStatus: jest.fn(),
  };

  beforeEach(async () => {
    schemaHealthcheck.getReadinessStatus.mockReturnValue({
      ready: true,
      checked: true,
      missingCount: 0,
    });

    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [
        AppService,
        {
          provide: SchemaHealthcheckService,
          useValue: schemaHealthcheck,
        },
      ],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  describe('root', () => {
    it('should return "Hello World!"', () => {
      expect(appController.getHello()).toBe('Hello World!');
    });
  });

  describe('health', () => {
    it('returns liveness without runtime internals', () => {
      const health = appController.health();

      expect(health).toMatchObject({ status: 'ok' });
      expect(health).not.toHaveProperty('memoryMB');
      expect(health).not.toHaveProperty('nodeVersion');
    });
  });

  describe('ready', () => {
    it('returns readiness when the schema contract is available', () => {
      expect(appController.ready()).toMatchObject({
        status: 'ok',
        checks: {
          schema: {
            ready: true,
            checked: true,
            missingCount: 0,
          },
        },
      });
    });

    it('fails closed when the schema contract is not ready', () => {
      schemaHealthcheck.getReadinessStatus.mockReturnValue({
        ready: false,
        checked: true,
        missingCount: 1,
        reason: 'missing_resources',
      });

      expect(() => appController.ready()).toThrow(HttpException);
    });
  });
});
