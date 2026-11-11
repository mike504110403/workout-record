// 單元測試:`node --test supabase/functions/apple-revoke/`(Node 20+,不需 deno)。
// Edge Function 本體(index.ts)未實跑,需部署後 smoke;這裡涵蓋所有純函式邏輯。
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { test } from 'node:test';

import {
  APPLE_AUDIENCE,
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  APPLE_FETCH_TIMEOUT_MS,
  CLIENT_SECRET_TTL_SEC,
  FAILURE_ERROR,
  FAILURE_STATUS,
  base64UrlDecodeToString,
  base64UrlEncode,
  buildClientSecret,
  decodeJwtPayload,
  extractBearerToken,
  getAppleSubFromUser,
  handleRevokeRequest,
  readAppleEnv,
  revokeAppleAuthorization,
} from './apple.js';

const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
const env = { teamId: 'TEAM123456', keyId: 'KEY1234567', clientId: 'com.mikelin.workitout', privateKey: pem };
const NOW = 1_800_000_000;

function fakeIdToken(sub) {
  return `${base64UrlEncode('{"alg":"none"}')}.${base64UrlEncode(JSON.stringify({ sub }))}.sig`;
}

/** 依序回應的 fetch 假件,並記錄每次呼叫。 */
function fakeFetch(responses) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    const r = responses[calls.length - 1];
    if (r instanceof Error) throw r;
    return { ok: r.status >= 200 && r.status < 300, status: r.status, json: async () => r.body ?? {} };
  };
  return { fn, calls };
}

test('client_secret:header/payload 欄位正確', async () => {
  const jwt = await buildClientSecret(env, NOW);
  const [h, p, s] = jwt.split('.');
  assert.ok(s.length > 0);
  assert.deepEqual(JSON.parse(base64UrlDecodeToString(h)), { alg: 'ES256', kid: env.keyId, typ: 'JWT' });
  assert.deepEqual(JSON.parse(base64UrlDecodeToString(p)), {
    iss: env.teamId,
    iat: NOW,
    exp: NOW + CLIENT_SECRET_TTL_SEC,
    aud: APPLE_AUDIENCE,
    sub: env.clientId,
  });
});

test('client_secret:ES256 簽章可用對應公鑰驗過(raw r||s 64 bytes)', async () => {
  const jwt = await buildClientSecret(env, NOW);
  const [h, p, s] = jwt.split('.');
  const sig = Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  assert.equal(sig.length, 64);
  const key = await crypto.subtle.importKey(
    'spki',
    publicKey.export({ type: 'spki', format: 'der' }),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    sig,
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert.equal(ok, true);
  // 竄改 payload 驗不過
  const tampered = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    sig,
    new TextEncoder().encode(`${h}.${base64UrlEncode('{"iss":"evil"}')}`),
  );
  assert.equal(tampered, false);
});

test('readAppleEnv:缺任一個就拋;PEM 字面 \\n 會還原', () => {
  const all = { APPLE_TEAM_ID: 't', APPLE_KEY_ID: 'k', APPLE_CLIENT_ID: 'c', APPLE_PRIVATE_KEY: 'a\\nb' };
  assert.deepEqual(readAppleEnv((k) => all[k]), { teamId: 't', keyId: 'k', clientId: 'c', privateKey: 'a\nb' });
  for (const missing of Object.keys(all)) {
    assert.throws(() => readAppleEnv((k) => (k === missing ? undefined : all[k])));
  }
});

test('getAppleSubFromUser:取 apple identity 的 sub,沒有則 null', () => {
  assert.equal(
    getAppleSubFromUser({ identities: [{ provider: 'google', id: 'g' }, { provider: 'apple', id: 'idv', identity_data: { sub: 'S1' } }] }),
    'S1',
  );
  assert.equal(getAppleSubFromUser({ identities: [{ provider: 'apple', id: 'ID-ONLY' }] }), 'ID-ONLY');
  assert.equal(getAppleSubFromUser({ identities: [{ provider: 'email', id: 'x' }] }), null);
  assert.equal(getAppleSubFromUser({}), null);
  assert.equal(getAppleSubFromUser(null), null);
});

test('decodeJwtPayload / extractBearerToken', () => {
  assert.deepEqual(decodeJwtPayload(fakeIdToken('abc')), { sub: 'abc' });
  assert.equal(decodeJwtPayload('not-a-jwt'), null);
  assert.equal(decodeJwtPayload(undefined), null);
  assert.equal(extractBearerToken('Bearer abc.def'), 'abc.def');
  assert.equal(extractBearerToken('bearer  x'), 'x');
  assert.equal(extractBearerToken('Basic x'), null);
  assert.equal(extractBearerToken(null), null);
});

test('revoke 成功:先 token 再 revoke,body 欄位正確,revoke 用換到的 refresh_token', async () => {
  const { fn, calls } = fakeFetch([
    { status: 200, body: { refresh_token: 'RT-1', id_token: fakeIdToken('SUB-1') } },
    { status: 200 },
  ]);
  const result = await revokeAppleAuthorization({
    authorizationCode: 'CODE-1', expectedAppleSub: 'SUB-1', env, fetchFn: fn, nowSec: NOW,
  });
  assert.deepEqual(result, { ok: true });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, APPLE_TOKEN_URL);
  assert.equal(calls[1].url, APPLE_REVOKE_URL);
  const tokenForm = new URLSearchParams(calls[0].init.body);
  assert.equal(tokenForm.get('grant_type'), 'authorization_code');
  assert.equal(tokenForm.get('code'), 'CODE-1');
  assert.equal(tokenForm.get('client_id'), env.clientId);
  assert.ok(tokenForm.get('client_secret').split('.').length === 3);
  const revokeForm = new URLSearchParams(calls[1].init.body);
  assert.equal(revokeForm.get('token'), 'RT-1');
  assert.equal(revokeForm.get('token_type_hint'), 'refresh_token');
  assert.equal(calls[0].init.headers['Content-Type'], 'application/x-www-form-urlencoded');
});

test('sub 與呼叫者不符:不撤銷(只打了 token,沒打 revoke)', async () => {
  const { fn, calls } = fakeFetch([
    { status: 200, body: { refresh_token: 'RT-1', id_token: fakeIdToken('OTHER-PERSON') } },
  ]);
  const result = await revokeAppleAuthorization({
    authorizationCode: 'C', expectedAppleSub: 'SUB-1', env, fetchFn: fn, nowSec: NOW,
  });
  assert.deepEqual(result, { ok: false, stage: 'sub_mismatch' });
  assert.equal(calls.length, 1);
});

test('id_token 缺失/解不出 sub:視為不符,不撤銷', async () => {
  for (const idToken of [undefined, 'garbage', fakeIdToken('')]) {
    const { fn, calls } = fakeFetch([{ status: 200, body: { refresh_token: 'RT', id_token: idToken } }]);
    const result = await revokeAppleAuthorization({
      authorizationCode: 'C', expectedAppleSub: 'SUB-1', env, fetchFn: fn, nowSec: NOW,
    });
    assert.equal(result.stage, 'sub_mismatch');
    assert.equal(calls.length, 1);
  }
});

test('Apple 端失敗:token 階段非 2xx / 缺 refresh_token / 網路錯誤 / revoke 非 2xx', async () => {
  const run = (responses) => {
    const { fn } = fakeFetch(responses);
    return revokeAppleAuthorization({ authorizationCode: 'C', expectedAppleSub: 'S', env, fetchFn: fn, nowSec: NOW });
  };
  assert.deepEqual(await run([{ status: 400 }]), { ok: false, stage: 'token', status: 400 });
  assert.deepEqual(await run([{ status: 200, body: {} }]), { ok: false, stage: 'token' });
  assert.deepEqual(await run([new Error('net')]), { ok: false, stage: 'token' });
  assert.deepEqual(
    await run([{ status: 200, body: { refresh_token: 'R', id_token: fakeIdToken('S') } }, { status: 401 }]),
    { ok: false, stage: 'revoke', status: 401 },
  );
});

test('私鑰壞掉:sign 階段失敗,完全不打 Apple', async () => {
  const { fn, calls } = fakeFetch([]);
  const result = await revokeAppleAuthorization({
    authorizationCode: 'C', expectedAppleSub: 'S', env: { ...env, privateKey: 'garbage' }, fetchFn: fn, nowSec: NOW,
  });
  assert.deepEqual(result, { ok: false, stage: 'sign' });
  assert.equal(calls.length, 0);
});

// ---- handleRevokeRequest:呼叫者驗證與整體分支 ----

const appleUser = { id: 'u1', identities: [{ provider: 'apple', id: 'SUB-1', identity_data: { sub: 'SUB-1' } }] };

function handle(overrides) {
  const { fn, calls } = fakeFetch(overrides.responses ?? [
    { status: 200, body: { refresh_token: 'RT', id_token: fakeIdToken('SUB-1') } },
    { status: 200 },
  ]);
  const getUserCalls = [];
  return handleRevokeRequest({
    authHeader: 'Bearer user.jwt.here',
    body: { authorizationCode: 'CODE' },
    getUser: async (jwt) => {
      getUserCalls.push(jwt);
      return appleUser;
    },
    getEnv: () => env,
    fetchFn: fn,
    nowSec: NOW,
    ...overrides,
  }).then((r) => ({ ...r, calls, getUserCalls }));
}

test('handle:正常 → 200 { ok: true },用請求的 JWT 驗呼叫者', async () => {
  const r = await handle({});
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { ok: true });
  assert.deepEqual(r.getUserCalls, ['user.jwt.here']);
  assert.equal(r.calls.length, 2);
});

test('handle:沒有 Authorization / getUser 回 null 或拋 → 401,完全不打 Apple', async () => {
  for (const o of [
    { authHeader: null },
    { authHeader: 'Basic x' },
    { getUser: async () => null },
    { getUser: async () => { throw new Error('bad jwt'); } },
  ]) {
    const r = await handle(o);
    assert.equal(r.status, 401);
    assert.deepEqual(r.body, { ok: false, error: 'unauthorized' });
    assert.equal(r.calls.length, 0);
  }
});

// 對外回應收斂:除了未登入 401,所有失敗都是同一個狀態碼與 { ok: false, error: 'revoke_failed' },
// 呼叫端無法區分是哪個階段(特別是 sub_mismatch 不能從回應看出)。
const FAILURE_BODY = { ok: false, error: FAILURE_ERROR };

test('handle:authorizationCode 缺失/非字串 → 統一失敗回應,不打 Apple', async () => {
  for (const body of [null, {}, { authorizationCode: '' }, { authorizationCode: 5 }]) {
    const r = await handle({ body });
    assert.equal(r.status, FAILURE_STATUS);
    assert.deepEqual(r.body, FAILURE_BODY);
    assert.equal(r.calls.length, 0);
  }
});

test('handle:呼叫者沒有 Apple 身分 → 統一失敗回應,不打 Apple', async () => {
  const r = await handle({ getUser: async () => ({ id: 'u2', identities: [{ provider: 'email', id: 'e' }] }) });
  assert.equal(r.status, FAILURE_STATUS);
  assert.deepEqual(r.body, FAILURE_BODY);
  assert.equal(r.calls.length, 0);
});

test('handle:環境未設定 → 統一失敗回應,不打 Apple', async () => {
  const r = await handle({ getEnv: () => { throw new Error('x'); } });
  assert.equal(r.status, FAILURE_STATUS);
  assert.deepEqual(r.body, FAILURE_BODY);
  assert.equal(r.calls.length, 0);
});

test('handle:Apple sub 不符不撤銷;Apple 端失敗;兩者對外回應完全相同且不含 Apple 回應內容', async () => {
  const mismatch = await handle({
    responses: [{ status: 200, body: { refresh_token: 'RT', id_token: fakeIdToken('SOMEONE-ELSE') } }],
  });
  assert.equal(mismatch.calls.length, 1, 'sub 不符只打 token、不打 revoke');

  const upstream = await handle({ responses: [{ status: 400, body: { error: 'invalid_grant', secret: 'LEAK' } }] });
  const revokeFail = await handle({
    responses: [{ status: 200, body: { refresh_token: 'RT', id_token: fakeIdToken('SUB-1') } }, { status: 503 }],
  });

  for (const r of [mismatch, upstream, revokeFail]) {
    assert.equal(r.status, FAILURE_STATUS);
    assert.deepEqual(r.body, FAILURE_BODY);
  }
  assert.ok(!JSON.stringify(upstream.body).includes('LEAK'));
});

test('handle:log 記階段與 Apple HTTP 狀態碼,且不含 token/code/金鑰/Apple 回應內容', async () => {
  const entries = [];
  const log = (e) => entries.push(e);
  await handle({ log, responses: [{ status: 400, body: { error: 'LEAK-BODY' } }] });
  await handle({
    log,
    responses: [{ status: 200, body: { refresh_token: 'RT-SECRET', id_token: fakeIdToken('SUB-1') } }, { status: 503 }],
  });
  await handle({
    log,
    responses: [{ status: 200, body: { refresh_token: 'RT-SECRET', id_token: fakeIdToken('SOMEONE-ELSE') } }],
  });
  await handle({ log });
  await handle({ log, authHeader: null });

  assert.deepEqual(entries, [
    { stage: 'token', appleStatus: 400 },
    { stage: 'revoke', appleStatus: 503 },
    { stage: 'sub_mismatch', appleStatus: null },
    { stage: 'ok', appleStatus: null },
    { stage: 'unauthorized', appleStatus: null },
  ]);
  const dumped = JSON.stringify(entries);
  for (const secret of ['LEAK-BODY', 'RT-SECRET', 'CODE', 'user.jwt.here', 'BEGIN PRIVATE KEY']) {
    assert.ok(!dumped.includes(secret), `log 不得含 ${secret}`);
  }
});

// ---- 對 Apple 的請求逾時 ----

// AbortSignal.timeout 的計時器是 unref 的,測試裡若沒有別的 handle 撐著,event loop 會
// 在逾時前就結束而把測試判成 cancelled;用一個 ref 的計時器撐住。
async function withKeepAlive(fn) {
  const keepAlive = setInterval(() => {}, 1000);
  try {
    return await fn();
  } finally {
    clearInterval(keepAlive);
  }
}

/** 尊重 AbortSignal 的永遠不回應 fetch:signal 中止時以 AbortError 拒絕(同真 fetch)。 */
function hangingFetch(calls) {
  return (url, init) => {
    calls.push({ url, init });
    return new Promise((_, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason));
    });
  };
}

test('timeout:每個 Apple 請求都帶 AbortSignal,預設 10 秒', async () => {
  assert.equal(APPLE_FETCH_TIMEOUT_MS, 10000);
  const { fn, calls } = fakeFetch([
    { status: 200, body: { refresh_token: 'RT-1', id_token: fakeIdToken('SUB-1') } },
    { status: 200 },
  ]);
  await revokeAppleAuthorization({
    authorizationCode: 'C', expectedAppleSub: 'SUB-1', env, fetchFn: fn, nowSec: NOW,
  });
  assert.equal(calls.length, 2);
  for (const c of calls) {
    assert.ok(c.init.signal instanceof AbortSignal, '請求必須帶 signal');
    assert.equal(c.init.signal.aborted, false);
  }
});

test('timeout:token 階段 Apple 不回應 → 逾時後 token 階段失敗(不掛住)', async () => {
  const calls = [];
  const result = await withKeepAlive(() => revokeAppleAuthorization({
    authorizationCode: 'C', expectedAppleSub: 'S', env, fetchFn: hangingFetch(calls), nowSec: NOW, timeoutMs: 30,
  }));
  assert.deepEqual(result, { ok: false, stage: 'token' });
  assert.equal(calls.length, 1);
  assert.ok(calls[0].init.signal instanceof AbortSignal, '逾時必須是靠 signal 中止的');
  assert.equal(calls[0].init.signal.aborted, true);
});

test('timeout:revoke 階段 Apple 不回應 → 逾時後 revoke 階段失敗', async () => {
  const calls = [];
  const fn = (url, init) => {
    if (url === APPLE_TOKEN_URL) {
      calls.push(url);
      return Promise.resolve({
        ok: true, status: 200,
        json: async () => ({ refresh_token: 'RT', id_token: fakeIdToken('S') }),
      });
    }
    return hangingFetch(calls)(url, init);
  };
  const result = await withKeepAlive(() => revokeAppleAuthorization({
    authorizationCode: 'C', expectedAppleSub: 'S', env, fetchFn: fn, nowSec: NOW, timeoutMs: 30,
  }));
  assert.deepEqual(result, { ok: false, stage: 'revoke' });
});
