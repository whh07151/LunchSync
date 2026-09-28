import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ObservabilityController } from './observability.controller';
import { ObservabilityService } from './observability.service';

describe('ObservabilityController', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('hides runtime diagnostics in production when no token is configured', () => {
    process.env.NODE_ENV = 'production';
    delete process.env.OBSERVABILITY_TOKEN;

    const controller = new ObservabilityController(new ObservabilityService());

    expect(() => controller.runtime()).toThrow(NotFoundException);
  });

  it('requires the configured diagnostics token', () => {
    process.env.NODE_ENV = 'production';
    process.env.OBSERVABILITY_TOKEN = 'release-secret';

    const controller = new ObservabilityController(new ObservabilityService());

    expect(() => controller.runtime('wrong')).toThrow(ForbiddenException);
    expect(controller.runtime('release-secret')).toMatchObject({ status: 'ok' });
  });
});
