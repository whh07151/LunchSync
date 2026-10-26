import assert from 'node:assert/strict';
import test from 'node:test';

import { validateHealthResponse } from '../scripts/validate-health-response.mjs';

const validResponse = {
  status: 'ok',
  uptimeSeconds: 120,
  memoryMB: { rss: 82, heapUsed: 31 },
  timestamp: '2026-10-26T00:00:00.000Z',
  nodeVersion: 'v20.20.2',
};

test('accepts the documented LunchSync health response', () => {
  assert.equal(validateHealthResponse(validResponse), validResponse);
});

test('rejects a non-healthy status', () => {
  assert.throws(() => validateHealthResponse({ ...validResponse, status: 'down' }), /status must be "ok"/);
});

test('rejects missing memory data', () => {
  const { memoryMB, ...response } = validResponse;
  assert.throws(() => validateHealthResponse(response), /memoryMB must be an object/);
});

test('rejects an invalid timestamp or Node.js version', () => {
  assert.throws(() => validateHealthResponse({ ...validResponse, timestamp: 'not-a-date' }), /timestamp/);
  assert.throws(() => validateHealthResponse({ ...validResponse, nodeVersion: 'unknown' }), /nodeVersion/);
});
