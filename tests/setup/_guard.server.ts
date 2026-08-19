/**
 * Phase 5D-2R Isolated Test Guard.
 *
 * Refuses to execute ANY runtime harness action unless we can prove the
 * caller is pointed at a dedicated Test Supabase project — never the
 * production project.
 *
 * The synchronous availability check is env-only. An asynchronous marker
 * check (`assertTestMarker`) verifies the DB row and MUST be called from
 * every runtime `beforeAll` — when the environment is configured but the
 * marker is missing/invalid, that call throws hard rather than skipping.
 */

export const PRODUCTION_PROJECT_REF = "omgrldatyncodeabecia";
export const PRODUCTION_HOST = `${PRODUCTION_PROJECT_REF}.supabase.co`;

export const REQUIRED_TEST_PROJECT_REF = "kmmegunjvssclsjlarun";
export const REQUIRED_TEST_URL = "https://kmmegunjvssclsjlarun.supabase.co";

export type GuardErrorCode =
  | "PRODUCTION_PROJECT_BLOCKED"
  | "TEST_PROJECT_REQUIRED"
  | "TEST_PROJECT_REF_MISMATCH"
  | "TEST_PROJECT_URL_MISMATCH"
  | "TEST_FIXTURES_DISABLED"
  | "TEST_SERVICE_ROLE_MISSING"
  | "TEST_ANON_KEY_MISSING"
  | "TEST_PROJECT_MARKER_MISSING"
  | "TEST_PROJECT_MARKER_INVALID"
  | "TEST_ENVIRONMENT_INVALID";

export class GuardError extends Error {
  constructor(public readonly code: GuardErrorCode, message: string) {
    super(`[${code}] ${message}`);
    this.name = "GuardError";
  }
}

export interface GuardResult {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
  testRunId: string;
  expectedProjectRef: string;
  projectRef: string;
}

const REQUIRED_TRUE_FIELDS = ["TEST_ENVIRONMENT", "ALLOW_TEST_FIXTURES"] as const;
const REQUIRED_NON_EMPTY_FIELDS = [
  "SUPABASE_TEST_URL",
  "SUPABASE_TEST_ANON_KEY",
  "SUPABASE_TEST_SERVICE_ROLE_KEY",
  "EXPECTED_TEST_PROJECT_REF",
] as const;
const PRODUCTION_SCANNED_FIELDS = [
  "EXPECTED_TEST_PROJECT_REF",
  "SUPABASE_TEST_URL",
  "SUPABASE_DB_URL",
  "DATABASE_URL",
] as const;

export interface RuntimeEnvironmentDiagnostics {
  configured: boolean;
  invalidFields: string[];
  ci: boolean;
  localSkipReason?: string;
}

function isNonEmpty(value: string | undefined): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

export function runtimeEnvironmentInvalidFields(env: NodeJS.ProcessEnv = process.env): string[] {
  const invalid = new Set<string>();

  for (const field of REQUIRED_TRUE_FIELDS) {
    if (env[field] !== "true") invalid.add(field);
  }
  if (env.APP_ENV !== "test") invalid.add("APP_ENV");

  for (const field of REQUIRED_NON_EMPTY_FIELDS) {
    if (!isNonEmpty(env[field])) invalid.add(field);
  }

  if (env.EXPECTED_TEST_PROJECT_REF !== REQUIRED_TEST_PROJECT_REF) {
    invalid.add("EXPECTED_TEST_PROJECT_REF");
  }
  if (env.SUPABASE_TEST_URL !== REQUIRED_TEST_URL) {
    invalid.add("SUPABASE_TEST_URL");
  }

  for (const field of PRODUCTION_SCANNED_FIELDS) {
    const value = env[field];
    if (value?.includes(PRODUCTION_PROJECT_REF) || value?.includes(PRODUCTION_HOST)) {
      invalid.add(field);
    }
  }

  return Array.from(invalid).sort();
}

export function runtimeEnvironmentConfigured(): boolean {
  return runtimeEnvironmentInvalidFields().length === 0;
}

export function runtimeEnvironmentDiagnostics(env: NodeJS.ProcessEnv = process.env): RuntimeEnvironmentDiagnostics {
  const invalidFields = runtimeEnvironmentInvalidFields(env);
  const configured = invalidFields.length === 0;
  return {
    configured,
    invalidFields,
    ci: env.CI === "true",
    localSkipReason:
      !configured && env.CI !== "true"
        ? `LOCAL_RUNTIME_UNCONFIGURED: ${invalidFields.join(", ")}`
        : undefined,
  };
}

export function localRuntimeSkipReason(env: NodeJS.ProcessEnv = process.env): string | undefined {
  return runtimeEnvironmentDiagnostics(env).localSkipReason;
}

export function assertRuntimeEnvironmentConfigured(): GuardResult {
  const invalidFields = runtimeEnvironmentInvalidFields();
  if (invalidFields.length > 0) {
    const prefix = process.env.CI === "true" ? "Runtime environment invalid" : "LOCAL_RUNTIME_UNCONFIGURED";
    throw new GuardError("TEST_ENVIRONMENT_INVALID", `${prefix}: ${invalidFields.join(", ")}`);
  }

  return assertTestEnvironment();
}

/**
 * Synchronous env-only assertion. No DB access.
 * Enforces the exact pinned Test project ref and URL, and rejects the
 * production ref anywhere it could appear.
 */
export function assertTestEnvironment(): GuardResult {
  if (process.env.TEST_ENVIRONMENT !== "true") {
    throw new GuardError("TEST_ENVIRONMENT_INVALID", "TEST_ENVIRONMENT must equal 'true'.");
  }
  if (process.env.APP_ENV !== "test") {
    throw new GuardError("TEST_ENVIRONMENT_INVALID", "APP_ENV must equal 'test'.");
  }
  if (process.env.ALLOW_TEST_FIXTURES !== "true") {
    throw new GuardError("TEST_FIXTURES_DISABLED", "ALLOW_TEST_FIXTURES must equal 'true'.");
  }

  const supabaseUrl = process.env.SUPABASE_TEST_URL;
  const anonKey = process.env.SUPABASE_TEST_ANON_KEY;
  const serviceRoleKey = process.env.SUPABASE_TEST_SERVICE_ROLE_KEY;
  const expectedProjectRef = process.env.EXPECTED_TEST_PROJECT_REF;
  const testRunId = process.env.TEST_RUN_ID ?? `local-${Date.now()}`;

  if (!supabaseUrl) throw new GuardError("TEST_PROJECT_REQUIRED", "SUPABASE_TEST_URL missing.");
  if (!anonKey) throw new GuardError("TEST_ANON_KEY_MISSING", "SUPABASE_TEST_ANON_KEY missing.");
  if (!serviceRoleKey) throw new GuardError("TEST_SERVICE_ROLE_MISSING", "SUPABASE_TEST_SERVICE_ROLE_KEY missing.");
  if (!expectedProjectRef) throw new GuardError("TEST_PROJECT_REQUIRED", "EXPECTED_TEST_PROJECT_REF missing.");

  // Production denylist — hard block first.
  if (
    expectedProjectRef === PRODUCTION_PROJECT_REF ||
    supabaseUrl.includes(PRODUCTION_HOST) ||
    supabaseUrl.includes(PRODUCTION_PROJECT_REF)
  ) {
    throw new GuardError(
      "PRODUCTION_PROJECT_BLOCKED",
      "Refusing to run: URL or EXPECTED_TEST_PROJECT_REF matches production project.",
    );
  }

  // Pinned isolated Test project — literal values required.
  if (expectedProjectRef !== REQUIRED_TEST_PROJECT_REF) {
    throw new GuardError(
      "TEST_PROJECT_REF_MISMATCH",
      `EXPECTED_TEST_PROJECT_REF must equal the pinned isolated Test project ref.`,
    );
  }
  if (supabaseUrl !== REQUIRED_TEST_URL) {
    throw new GuardError(
      "TEST_PROJECT_URL_MISMATCH",
      `SUPABASE_TEST_URL must equal the pinned isolated Test project URL.`,
    );
  }

  return {
    supabaseUrl,
    anonKey,
    serviceRoleKey,
    testRunId,
    expectedProjectRef,
    projectRef: expectedProjectRef,
  };
}

/**
 * Verifies the DB-side test_environment_marker row.
 * MUST be called from every runtime beforeAll with a service-role client
 * AFTER `assertTestEnvironment()`. Throws hard on missing/invalid marker —
 * runtime tests never silently skip after CI provisioning succeeds.
 */
export async function assertTestMarker(
  admin: { from: (t: string) => any },
  env: GuardResult,
): Promise<void> {
  const { data, error } = await admin
    .from("test_environment_marker")
    .select("environment_name, project_ref, test_fixtures_allowed")
    .maybeSingle();

  if (error) {
    throw new GuardError(
      "TEST_PROJECT_MARKER_MISSING",
      `test_environment_marker query failed: ${error.message ?? "unknown"}`,
    );
  }
  if (!data) {
    throw new GuardError(
      "TEST_PROJECT_MARKER_MISSING",
      "test_environment_marker row not found on the isolated Test project.",
    );
  }
  if (data.environment_name !== "test") {
    throw new GuardError("TEST_PROJECT_MARKER_INVALID", "environment_name is not 'test'.");
  }
  if (data.project_ref !== REQUIRED_TEST_PROJECT_REF || data.project_ref !== env.expectedProjectRef) {
    throw new GuardError(
      "TEST_PROJECT_MARKER_INVALID",
      "test_environment_marker project_ref does not match pinned isolated Test project ref.",
    );
  }
  if (data.test_fixtures_allowed !== true) {
    throw new GuardError(
      "TEST_PROJECT_MARKER_INVALID",
      "test_environment_marker.test_fixtures_allowed is not true.",
    );
  }
}

export function scopeToTestRun<T extends Record<string, unknown>>(row: T, testRunId: string): T {
  return { ...row, metadata: { ...(row.metadata as object | undefined ?? {}), test_run_id: testRunId } };
}
