import { ObservabilityService } from './observability.service';

describe('ObservabilityService', () => {
  it('returns a runtime snapshot with bounded numeric fields', () => {
    const snapshot = new ObservabilityService().snapshot();

    expect(snapshot.status).toBe('ok');
    expect(snapshot.service).toBeTruthy();
    expect(snapshot.uptimeSeconds).toBeGreaterThanOrEqual(0);
    expect(snapshot.memoryMB.rss).toBeGreaterThan(0);
    expect(snapshot.memoryMB.heapTotal).toBeGreaterThan(0);
    expect(snapshot.eventLoopUtilization.utilization).toBeGreaterThanOrEqual(0);
    expect(snapshot.eventLoopUtilization.utilization).toBeLessThanOrEqual(1);
    expect(new Date(snapshot.timestamp).toString()).not.toBe('Invalid Date');
  });
});
