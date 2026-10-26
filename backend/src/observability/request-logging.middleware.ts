import { Injectable, Logger, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { NextFunction, Request, Response } from 'express';

const REQUEST_ID_HEADER = 'x-request-id';
const SAFE_REQUEST_ID = /^[A-Za-z0-9._:-]{1,128}$/;

@Injectable()
export class RequestLoggingMiddleware implements NestMiddleware {
  private readonly logger = new Logger('HttpRequest');

  use(req: Request, res: Response, next: NextFunction): void {
    const startedAt = process.hrtime.bigint();
    const requestId = this.resolveRequestId(req);

    res.setHeader(REQUEST_ID_HEADER, requestId);

    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
      const payload = {
        requestId,
        method: req.method,
        route: this.resolveRoute(req),
        statusCode: res.statusCode,
        durationMs: Number(durationMs.toFixed(1)),
      };

      const message = JSON.stringify(payload);
      if (res.statusCode >= 500) {
        this.logger.error(message);
      } else if (res.statusCode >= 400) {
        this.logger.warn(message);
      } else {
        this.logger.log(message);
      }
    });

    next();
  }

  private resolveRequestId(req: Request): string {
    const incoming = req.header(REQUEST_ID_HEADER);
    if (incoming) {
      const candidate = incoming.trim();
      if (SAFE_REQUEST_ID.test(candidate)) {
        return candidate;
      }
    }

    return randomUUID();
  }

  private resolveRoute(req: Request): string {
    const routePath = req.route?.path as unknown;
    if (typeof routePath === 'string') {
      return `${req.baseUrl ?? ''}${routePath}`;
    }

    // Unmatched paths have no safe route template. Never log their raw path:
    // capability URLs such as invite links can still carry secrets in segments.
    return 'unmatched';
  }
}
