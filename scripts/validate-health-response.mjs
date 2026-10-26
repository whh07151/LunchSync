import { pathToFileURL } from 'node:url';

function requireCondition(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

export function validateHealthResponse(value) {
  requireCondition(value && typeof value === 'object' && !Array.isArray(value), 'response must be a JSON object');
  requireCondition(value.status === 'ok', 'status must be "ok"');
  requireCondition(Number.isInteger(value.uptimeSeconds) && value.uptimeSeconds >= 0, 'uptimeSeconds must be a non-negative integer');
  requireCondition(value.memoryMB && typeof value.memoryMB === 'object', 'memoryMB must be an object');

  for (const field of ['rss', 'heapUsed']) {
    requireCondition(Number.isFinite(value.memoryMB[field]) && value.memoryMB[field] >= 0, `memoryMB.${field} must be non-negative`);
  }

  requireCondition(typeof value.timestamp === 'string' && Number.isFinite(Date.parse(value.timestamp)), 'timestamp must be a valid ISO date');
  requireCondition(typeof value.nodeVersion === 'string' && /^v\d+\.\d+\.\d+/.test(value.nodeVersion), 'nodeVersion must be a semantic Node.js version');

  return value;
}

async function main() {
  let input = '';
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  requireCondition(input.trim().length > 0, 'health response body is empty');
  const result = validateHealthResponse(JSON.parse(input));
  process.stdout.write(`Health contract valid: ${result.status}, ${result.nodeVersion}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Health contract invalid: ${error.message}\n`);
    process.exitCode = 1;
  });
}
