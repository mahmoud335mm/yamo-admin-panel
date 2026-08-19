/**
 * Phase 5D-2R shared fixtures — read side.
 *
 * The Vitest global setup (tests/runtime/5d2/global-setup.ts) provisions
 * every harness user, mints their sessions ONCE per Vitest invocation and
 * writes a runner-only file at RUNTIME_FIXTURE_FILE. Every runtime spec
 * MUST read that file with `loadSharedFixtures()` instead of calling
 * provisionTestUsers / assignTestRoles / mintAllSessions itself.
 *
 * The file never contains passwords. Only the minimum required IDs and
 * per-session access tokens (in-memory only, never logged) are stored.
 */
import { readFileSync } from "node:fs";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { assertRuntimeEnvironmentConfigured } from "../../setup/_guard.server";

export interface SharedSession {
  handle: string;
  role: string | null;
  userId: string;
  accessToken: string; // in-memory; NEVER logged or serialized to a spec-visible surface
  client: SupabaseClient;
}

export interface SharedFixtures {
  testRunId: string;
  fixtureScope: string;
  sessions: Record<string, SharedSession>;
}

interface StoredSession {
  handle: string;
  role: string | null;
  userId: string;
  accessToken: string;
}

interface StoredFixtures {
  testRunId: string;
  fixtureScope: string;
  users: StoredSession[];
}

let _cache: SharedFixtures | undefined;

export function sharedFixtureFilePath(): string {
  const p = process.env.RUNTIME_FIXTURE_FILE;
  if (!p) throw new Error("RUNTIME_FIXTURE_FILE is not set — did the global setup run?");
  return p;
}

export function specScope(spec: string): string {
  const { testRunId } = assertRuntimeEnvironmentConfigured();
  return `${testRunId}__${spec}`;
}

export function loadSharedFixtures(): SharedFixtures {
  if (_cache) return _cache;
  const env = assertRuntimeEnvironmentConfigured();
  const raw = readFileSync(sharedFixtureFilePath(), "utf8");
  const parsed = JSON.parse(raw) as StoredFixtures;

  const sessions: Record<string, SharedSession> = {};
  for (const u of parsed.users) {
    const client = createClient(env.supabaseUrl, env.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${u.accessToken}` } },
    });
    sessions[u.handle] = {
      handle: u.handle,
      role: u.role,
      userId: u.userId,
      accessToken: u.accessToken,
      client,
    };
  }

  _cache = {
    testRunId: parsed.testRunId,
    fixtureScope: parsed.fixtureScope,
    sessions,
  };
  return _cache;
}
