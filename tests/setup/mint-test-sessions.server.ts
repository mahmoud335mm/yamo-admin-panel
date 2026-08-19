/**
 * Phase 5D-2R: mints per-user JWT sessions via signInWithPassword.
 *
 * service_role is used ONLY for provisioning; runtime tests act as the
 * signed-in user through anon client + password sign-in.
 *
 * All error paths use the same safe Auth-error fields as provisioning
 * (name / message / status / code / __isAuthError). Passwords, refresh
 * tokens, JWTs and request objects are NEVER logged or serialized.
 *
 * A bounded retry (max 3 attempts, exponential backoff) is applied only
 * for HTTP 429 or explicitly retryable Auth errors. Invalid credentials
 * and other permanent errors fail immediately.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { assertTestEnvironment } from "./_guard.server";
import type { ProvisionedUser } from "./create-test-users.server";
import { formatSafeAuthError, safeAuthErrorDetails } from "./safe-auth-error.server";

export interface UserSession {
  handle: string;
  role: string | null;
  userId: string;
  accessToken: string; // in-memory, never logged
  client: SupabaseClient;
}

const RETRY_DELAYS_MS = [250, 750, 2000] as const;
const RETRYABLE_CODES = new Set([
  "over_request_rate_limit",
  "rate_limit_exceeded",
  "request_timeout",
]);

function isRetryableAuthError(error: unknown): boolean {
  const details = safeAuthErrorDetails(error);
  if (details.status === 429) return true;
  if (details.status === 503 || details.status === 504) return true;
  if (details.code && RETRYABLE_CODES.has(details.code)) return true;
  return false;
}

async function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export async function mintUserJwt(user: ProvisionedUser): Promise<UserSession> {
  const env = assertTestEnvironment();
  const anon = createClient(env.supabaseUrl, env.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let lastError: unknown = undefined;
  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
    const { data, error } = await anon.auth.signInWithPassword({
      email: user.email,
      password: user.password,
    });
    if (!error && data.session) {
      const client = createClient(env.supabaseUrl, env.anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
      });
      return {
        handle: user.handle,
        role: user.role,
        userId: user.id,
        accessToken: data.session.access_token,
        client,
      };
    }
    lastError = error ?? new Error("signIn returned no session");
    if (attempt === RETRY_DELAYS_MS.length || !isRetryableAuthError(error)) break;
    await sleep(RETRY_DELAYS_MS[attempt]);
  }
  throw new Error(`signIn(${user.handle}) failed: ${formatSafeAuthError(lastError)}`);
}

export async function mintAllSessions(users: ProvisionedUser[]): Promise<Record<string, UserSession>> {
  const out: Record<string, UserSession> = {};
  for (const u of users) out[u.handle] = await mintUserJwt(u);
  return out;
}
