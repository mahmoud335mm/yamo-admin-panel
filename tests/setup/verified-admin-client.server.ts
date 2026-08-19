/**
 * Phase 5D-2R: lazy service-role admin client for the Test project.
 * Never imported at module scope of any client-reachable file.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { assertTestEnvironment, assertTestMarker, type GuardResult } from "./_guard.server";

let _admin: SupabaseClient | undefined;
let _env: GuardResult | undefined;

export async function getVerifiedAdminClient(): Promise<{ admin: SupabaseClient; env: GuardResult }> {
  if (_admin && _env) return { admin: _admin, env: _env };
  const env = assertTestEnvironment();
  const admin = createClient(env.supabaseUrl, env.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  await assertTestMarker(admin, env);
  _admin = admin;
  _env = env;
  return { admin, env };
}

export function createAnonClient(env: GuardResult): SupabaseClient {
  return createClient(env.supabaseUrl, env.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
