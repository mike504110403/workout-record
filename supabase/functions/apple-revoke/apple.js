// Sign in with Apple 授權撤銷(App Store 5.1.1(v):刪帳號時須撤銷 Apple 授權)。
//
// 本檔是純 ESM JavaScript、只用 WebCrypto/URLSearchParams 等 Web 標準 API,不碰
// Deno 全域,所以 Deno(index.ts import)與 Node 20(`node --test`,見
// apple.test.js)都能直接載入。index.ts 只負責把 Deno.serve / Deno.env /
// supabase-js 接進來。
//
// 流程:驗呼叫者(index.ts 以請求的 Authorization 呼叫 auth.getUser)→ 比對呼叫者的
// Apple 身分 → 用 .p8 私鑰簽 ES256 client_secret JWT → POST /auth/token 用
// authorizationCode 換 refresh_token 與 id_token → 比對 id_token 的 sub 與呼叫者的
// Apple sub → 一致才 POST /auth/revoke 撤銷該 refresh_token。
//
// 隱私/安全:任何路徑都不得把 Apple 的回應內容、金鑰、client_secret、
// authorizationCode 寫進 log 或回傳給呼叫端。對外回應收斂成 { ok: true } 或
// { ok: false, error }(未登入 401,其餘失敗同一個狀態碼與代碼),不讓呼叫端從
// 回應區分失敗階段(例如 sub_mismatch 會洩漏「這個 code 屬於別的 Apple 帳號」);
// 階段與 Apple 的 HTTP 狀態碼只由伺服器端 log 記錄(見 handleRevokeRequest 的 log)。

export const APPLE_AUDIENCE = 'https://appleid.apple.com';
export const APPLE_TOKEN_URL = `${APPLE_AUDIENCE}/auth/token`;
export const APPLE_REVOKE_URL = `${APPLE_AUDIENCE}/auth/revoke`;

/** client_secret 只用一次,給短效期即可(Apple 上限 6 個月)。 */
export const CLIENT_SECRET_TTL_SEC = 300;

/** 對 Apple 每個請求的逾時(毫秒)。撤銷是盡力而為,Apple 卡住不能把函式吊到平台逾時。 */
export const APPLE_FETCH_TIMEOUT_MS = 10000;

/** 對外失敗回應:除未登入外,所有失敗共用同一個狀態碼與代碼。 */
export const FAILURE_STATUS = 400;
export const FAILURE_ERROR = 'revoke_failed';

/**
 * 從環境變數讀設定;缺任何一個就拋錯(呼叫端回 not_configured,不洩漏哪個缺)。
 * clientId = App 的 bundle id(原生 Sign in with Apple 的 client_id);
 * privateKey = .p8 的 PEM 全文(PKCS#8 EC P-256)。
 * @param {(key: string) => string | undefined} get
 * @returns {{ teamId: string, keyId: string, clientId: string, privateKey: string }}
 */
export function readAppleEnv(get) {
  const teamId = get('APPLE_TEAM_ID');
  const keyId = get('APPLE_KEY_ID');
  const clientId = get('APPLE_CLIENT_ID');
  const rawKey = get('APPLE_PRIVATE_KEY');
  if (!teamId || !keyId || !clientId || !rawKey) {
    throw new Error('apple env not configured');
  }
  // `supabase secrets set` 從單行字串帶入時換行常變成字面的 \n,還原回真換行。
  const privateKey = rawKey.includes('\\n') ? rawKey.replace(/\\n/g, '\n') : rawKey;
  return { teamId, keyId, clientId, privateKey };
}

/** @param {Uint8Array | string} input */
export function base64UrlEncode(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** @param {string} s base64url 字串 → UTF-8 字串 */
export function base64UrlDecodeToString(s) {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  return new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)));
}

/** PEM(PKCS#8)→ DER bytes,給 WebCrypto importKey('pkcs8') 用。 */
export function pemToPkcs8Der(pem) {
  const b64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/, '')
    .replace(/-----END [A-Z ]+-----/, '')
    .replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/**
 * 組並簽 Apple 要的 client_secret(ES256 JWT)。WebCrypto 的 ECDSA 簽章輸出
 * 本來就是 JWT 要的 raw r||s(IEEE P1363),不需要再轉 DER。
 * @param {{ teamId: string, keyId: string, clientId: string, privateKey: string }} env
 * @param {number} nowSec
 */
export async function buildClientSecret(env, nowSec) {
  const header = { alg: 'ES256', kid: env.keyId, typ: 'JWT' };
  const payload = {
    iss: env.teamId,
    iat: nowSec,
    exp: nowSec + CLIENT_SECRET_TTL_SEC,
    aud: APPLE_AUDIENCE,
    sub: env.clientId,
  };
  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8Der(env.privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
}

/** POST /auth/token 的 form body(authorization_code 換 refresh_token)。 */
export function buildTokenRequestBody(clientId, clientSecret, authorizationCode) {
  return new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: 'authorization_code',
  }).toString();
}

/** POST /auth/revoke 的 form body(撤銷 refresh_token)。 */
export function buildRevokeRequestBody(clientId, clientSecret, refreshToken) {
  return new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: 'refresh_token',
  }).toString();
}

/**
 * 解 JWT 的 payload(不驗簽)。只用在 Apple token endpoint 經 TLS 直接回給我們的
 * id_token——來源已可信,這裡只要讀 `sub`;不可拿來解任何外部輸入的 JWT。
 * 解不出來回 null。
 * @param {unknown} jwt
 */
export function decodeJwtPayload(jwt) {
  if (typeof jwt !== 'string') return null;
  const parts = jwt.split('.');
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(base64UrlDecodeToString(parts[1]));
    return payload && typeof payload === 'object' ? payload : null;
  } catch {
    return null;
  }
}

/**
 * 從 Supabase `auth.getUser()` 回的 user 取出 Apple 身分的 sub(= 原生登入的
 * `credential.userIdentifier`)。優先 `identity_data.sub`,退而用 identity 的
 * `id`(supabase 的 identity.id 即 provider 端的使用者 id)。沒有 apple identity 回 null。
 * @param {{ identities?: Array<{ provider?: string, id?: string, identity_data?: { sub?: string } }> } | null | undefined} user
 */
export function getAppleSubFromUser(user) {
  const identity = user?.identities?.find((i) => i?.provider === 'apple');
  if (!identity) return null;
  const sub = identity.identity_data?.sub ?? identity.id;
  return typeof sub === 'string' && sub !== '' ? sub : null;
}

/** @param {string | null | undefined} authHeader 取出 Bearer token,格式不對回 null。 */
export function extractBearerToken(authHeader) {
  if (!authHeader) return null;
  const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
  return match ? match[1] : null;
}

const FORM_HEADERS = { 'Content-Type': 'application/x-www-form-urlencoded' };

/**
 * 用 authorizationCode 換 refresh_token,確認 id_token 的 sub 就是呼叫者的 Apple
 * 身分後才撤銷。fetchFn / nowSec 可注入以便測試。Apple 回應只讀 refresh_token 與
 * id_token 的 sub,其餘一律丟棄、不記錄。
 *
 * sub 不符(裝置當下的 Apple ID 不是這個帳號,或有人拿別人的 code 來)→ 不撤銷、
 * 回 stage 'sub_mismatch'。
 *
 * @param {{
 *   authorizationCode: string,
 *   expectedAppleSub: string,
 *   env: { teamId: string, keyId: string, clientId: string, privateKey: string },
 *   fetchFn: (url: string, init: { method: string, headers: Record<string, string>, body: string, signal: AbortSignal }) => Promise<{ ok: boolean, status: number, json(): Promise<unknown> }>,
 *   nowSec: number,
 *   timeoutMs?: number,
 * }} args
 * @returns {Promise<{ ok: true } | { ok: false, stage: 'sign' | 'token' | 'sub_mismatch' | 'revoke', status?: number }>}
 */
export async function revokeAppleAuthorization(args) {
  const { authorizationCode, expectedAppleSub, env, fetchFn, nowSec } = args;
  const timeoutMs = args.timeoutMs ?? APPLE_FETCH_TIMEOUT_MS;

  let clientSecret;
  try {
    clientSecret = await buildClientSecret(env, nowSec);
  } catch {
    return { ok: false, stage: 'sign' };
  }

  let refreshToken;
  let tokenSub;
  try {
    const res = await fetchFn(APPLE_TOKEN_URL, {
      method: 'POST',
      headers: FORM_HEADERS,
      body: buildTokenRequestBody(env.clientId, clientSecret, authorizationCode),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) return { ok: false, stage: 'token', status: res.status };
    const body = await res.json();
    if (typeof body?.refresh_token === 'string' && body.refresh_token !== '') {
      refreshToken = body.refresh_token;
    }
    tokenSub = decodeJwtPayload(body?.id_token)?.sub;
  } catch {
    return { ok: false, stage: 'token' };
  }
  if (!refreshToken) return { ok: false, stage: 'token' };
  if (typeof tokenSub !== 'string' || tokenSub === '' || tokenSub !== expectedAppleSub) {
    return { ok: false, stage: 'sub_mismatch' };
  }

  try {
    const res = await fetchFn(APPLE_REVOKE_URL, {
      method: 'POST',
      headers: FORM_HEADERS,
      body: buildRevokeRequestBody(env.clientId, clientSecret, refreshToken),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) return { ok: false, stage: 'revoke', status: res.status };
  } catch {
    return { ok: false, stage: 'revoke' };
  }
  return { ok: true };
}

/**
 * 整個請求的處理(index.ts 只負責接 Deno 與 supabase-js)。回 `{ status, body }`。
 * 對外只有三種:200 `{ ok: true }`、401 `{ ok: false, error: 'unauthorized' }`、
 * 其餘失敗(body 格式錯、呼叫者沒有 Apple 身分、環境未設定、sub 不符、Apple 端失敗)
 * 一律 [FAILURE_STATUS] `{ ok: false, error: 'revoke_failed' }`。
 *
 * 實際階段與 Apple 的 HTTP 狀態碼只走 `log({ stage, appleStatus })`(index.ts 接
 * console.log)。**log 的內容只有階段名稱與數字狀態碼**——絕不放 token、code、金鑰、
 * Apple 回應內容或使用者識別。
 *
 * @param {{
 *   authHeader: string | null | undefined,
 *   body: unknown,
 *   getUser: (jwt: string) => Promise<{ identities?: unknown[] } | null>,
 *   getEnv: () => { teamId: string, keyId: string, clientId: string, privateKey: string },
 *   fetchFn: Parameters<typeof revokeAppleAuthorization>[0]['fetchFn'],
 *   nowSec: number,
 *   timeoutMs?: number,
 *   log?: (entry: { stage: string, appleStatus: number | null }) => void,
 * }} args
 * @returns {Promise<{ status: number, body: Record<string, unknown> }>}
 */
export async function handleRevokeRequest(args) {
  const { authHeader, body, getUser, getEnv, fetchFn, nowSec, timeoutMs } = args;
  const log = args.log ?? (() => {});
  const fail = (stage, appleStatus = null) => {
    log({ stage, appleStatus });
    return { status: FAILURE_STATUS, body: { ok: false, error: FAILURE_ERROR } };
  };

  const jwt = extractBearerToken(authHeader);
  if (!jwt) {
    log({ stage: 'unauthorized', appleStatus: null });
    return { status: 401, body: { ok: false, error: 'unauthorized' } };
  }
  let user;
  try {
    user = await getUser(jwt);
  } catch {
    user = null;
  }
  if (!user) {
    log({ stage: 'unauthorized', appleStatus: null });
    return { status: 401, body: { ok: false, error: 'unauthorized' } };
  }

  const authorizationCode = body?.authorizationCode;
  if (typeof authorizationCode !== 'string' || authorizationCode === '') {
    return fail('bad_request');
  }

  const expectedAppleSub = getAppleSubFromUser(user);
  if (!expectedAppleSub) return fail('no_apple_identity');

  let env;
  try {
    env = getEnv();
  } catch {
    return fail('not_configured');
  }

  const result = await revokeAppleAuthorization({
    authorizationCode,
    expectedAppleSub,
    env,
    fetchFn,
    nowSec,
    timeoutMs,
  });
  if (result.ok) {
    log({ stage: 'ok', appleStatus: null });
    return { status: 200, body: { ok: true } };
  }
  return fail(result.stage, result.status ?? null);
}
