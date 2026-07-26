import { Controller, Get } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { ObservabilityService } from './observability.service';
import type { RuntimeSnapshot } from './observability.service';

@Controller('observability')
export class ObservabilityController {
  constructor(private readonly observability: ObservabilityService) {}

  @SkipThrottle({ default: true, auth: true, signup: true })
  @Get('runtime')
  runtime(): RuntimeSnapshot {
    return this.observability.snapshot();
  }
}
