// Read-only Kakao discovery and registered-nearby checks against the isolated local stack.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { createClient } = require('@supabase/supabase-js');

const local = join(__dirname, '../../.local');
const status = JSON.parse(readFileSync(join(local, 'supabase-status.json'), 'utf8'));
const demo = JSON.parse(readFileSync(join(local, 'demo-accounts.json'), 'utf8'));
assert.ok(['127.0.0.1', 'localhost'].includes(new URL(status.API_URL).hostname));
const db = createClient(status.API_URL, status.SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const api = 'http://127.0.0.1:3000/api';

async function count(table) {
  const { count: result, error } = await db.from(table).select('id', { count: 'exact', head: true });
  if (error) throw new Error(`${table} count failed`);
  return result;
}

async function main() {
  const account = demo.accounts[0];
  const login = await fetch(`${api}/auth/login/email`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: account.email, password: account.password }),
    signal: AbortSignal.timeout(10000),
  });
  assert.equal(login.status, 201, 'local demo account login');
  const token = (await login.json()).data.accessToken;
  assert.ok(token);
  const before = await Promise.all([count('restaurants'), count('menu_items')]);
  const body = { lat: 37.5665, lng: 126.978, radius: 1000 };
  const nearby = await fetch(`${api}/crawl/nearby`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const payload = await nearby.json();
  assert.equal(nearby.status, 200,
    `nearby status ${nearby.status}; message ${JSON.stringify(payload.message ?? '')}`);
  assert.equal(payload.success, true);
  assert.ok(Array.isArray(payload.data));
  assert.ok(payload.data.length > 0, 'Kakao returned no restaurants for the synthetic city-center coordinate');
  for (const place of payload.data) {
    assert.equal(place.source, 'KAKAO');
    assert.match(place.kakaoUrl, /^https:\/\/place\.map\.kakao\.com\/\d+$/);
    assert.ok(place.distanceMeters >= 0 && place.distanceMeters <= 1000);
  }
  const registered = await fetch(`${api}/restaurants?lat=37.5665&lng=126.978&radius=1000&limit=10`, {
    headers: { authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(10000),
  });
  assert.equal(registered.status, 200);
  const registeredRows = (await registered.json()).data;
  assert.ok(Array.isArray(registeredRows));
  const after = await Promise.all([count('restaurants'), count('menu_items')]);
  assert.deepEqual(after, before, 'read-only discovery must not change restaurants or menus');
  console.log(`PASS Kakao nearby ${payload.data.length} places, registered ${registeredRows.length}, DB counts unchanged`);
}

main().catch((error) => {
  console.error('LOCAL_NEARBY_SMOKE_FAILED', error.message);
  process.exitCode = 1;
});
