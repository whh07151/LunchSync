import {
  Controller,
  ForbiddenException,
  Get,
  Headers,
  NotFoundException,
} from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { ObservabilityService } from './observability.service';
import type { RuntimeSnapshot } from './observability.service';

@Controller('observability')
export class ObservabilityController {
  constructor(private readonly observability: ObservabilityService) {}

  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('runtime')
  runtime(@Headers('x-observability-token') token?: string): RuntimeSnapshot {
    const configuredToken = process.env.OBSERVABILITY_TOKEN?.trim();
    if (process.env.NODE_ENV === 'production' && !configuredToken) {
      throw new NotFoundException();
    }
    if (configuredToken && token !== configuredToken) {
      throw new ForbiddenException();
    }

    return this.observability.snapshot();
  }
}
