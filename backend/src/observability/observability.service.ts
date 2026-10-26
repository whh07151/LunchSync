import { Injectable } from '@nestjs/common';
import { performance } from 'perf_hooks';

export interface RuntimeSnapshot {
  status: 'ok';
  service: string;
  uptimeSeconds: number;
  timestamp: string;
  nodeVersion: string;
  memoryMB: {
    rss: number;
    heapUsed: number;
    heapTotal: number;
  };
  eventLoopUtilization: {
    idle: number;
    active: number;
    utilization: number;
  };
}

@Injectable()
export class ObservabilityService {
  private readonly startedAt = Date.now();

  snapshot(): RuntimeSnapshot {
    const memory = process.memoryUsage();
    const elu = performance.eventLoopUtilization();

    return {
      status: 'ok',
      service: process.env.SERVICE_NAME ?? 'lunchsync-backend',
      uptimeSeconds: Math.floor((Date.now() - this.startedAt) / 1000),
      timestamp: new Date().toISOString(),
      nodeVersion: process.version,
      memoryMB: {
        rss: this.toMB(memory.rss),
        heapUsed: this.toMB(memory.heapUsed),
        heapTotal: this.toMB(memory.heapTotal),
      },
      eventLoopUtilization: {
        idle: Math.round(elu.idle),
        active: Math.round(elu.active),
        utilization: Number(elu.utilization.toFixed(4)),
      },
    };
  }

  private toMB(bytes: number): number {
    return Math.round(bytes / 1024 / 1024);
  }
}
