// Edge Function `apple-revoke`:刪帳號時撤銷 Sign in with Apple 授權。
// 邏輯都在 apple.js(純函式,有 `node --test` 單元測試);這裡只接
// Deno.serve / Deno.env / supabase-js。**本檔未實跑(本機沒有 deno),需部署後 smoke。**
//
// config.toml 設 `verify_jwt = false`,改在函式內自己驗呼叫者:用請求的 Authorization
// header 建 supabase client 呼叫 `auth.getUser()`(會向 Auth 伺服器驗證,anon key
// 或過期 JWT 都會失敗 → 401)。取得的 user 的 Apple 身分再與 Apple 換 token 後
// id_token 的 sub 比對,不一致不撤銷(見 apple.js)。
//
// 呼叫:App 在 RPC delete_my_account **之前**以使用者 JWT 呼叫(之後 JWT 就失效),
// body `{ "authorizationCode": "<Apple 重新授權取得的一次性 code>" }`。
// 回應只有 `{ ok: true }`、401 `{ ok: false, error: "unauthorized" }`、其餘失敗一律
// 同一狀態碼的 `{ ok: false, error: "revoke_failed" }`(不帶階段/Apple 狀態碼);
// 階段與 Apple HTTP 狀態碼只 console.log 在伺服器端(絕不記 token/code/金鑰/回應內容)。
//
// Secrets(部署時設定):APPLE_TEAM_ID、APPLE_KEY_ID、APPLE_CLIENT_ID(= bundle id)、
// APPLE_PRIVATE_KEY(.p8 PEM 全文)。SUPABASE_URL / SUPABASE_ANON_KEY 由平台注入。
import { createClient } from 'npm:@supabase/supabase-js@2';

import { FAILURE_ERROR, FAILURE_STATUS, handleRevokeRequest, readAppleEnv } from './apple.js';

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ ok: false, error: FAILURE_ERROR }, FAILURE_STATUS);

  let body: unknown = null;
  try {
    body = await req.json();
  } catch {
    // body 解不出來交給 handleRevokeRequest 回 bad_request(但未登入仍先回 401)。
  }

  const result = await handleRevokeRequest({
    authHeader: req.headers.get('Authorization'),
    body,
    getUser: async (jwt: string) => {
      const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await client.auth.getUser(jwt);
      return error ? null : data.user;
    },
    getEnv: () => readAppleEnv((key) => Deno.env.get(key)),
    fetchFn: (url, init) => fetch(url, init),
    nowSec: Math.floor(Date.now() / 1000),
    // 只有階段名稱與數字狀態碼,見 handleRevokeRequest 的 log 說明。
    log: (entry: { stage: string; appleStatus: number | null }) =>
      console.log(`apple-revoke stage=${entry.stage} appleStatus=${entry.appleStatus ?? '-'}`),
  });
  return json(result.body, result.status);
});
