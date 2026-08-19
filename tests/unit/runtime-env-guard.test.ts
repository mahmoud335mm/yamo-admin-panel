import { describe, expect, it } from "vitest";
import {
  assertRuntimeEnvironmentConfigured,
  PRODUCTION_PROJECT_REF,
  runtimeEnvironmentConfigured,
  runtimeEnvironmentDiagnostics,
} from "../setup/_guard.server";

function withEnv(env: Record<string, string | undefined>, fn: () => void) {
  const prev = { ...process.env };
  for (const key of Object.keys(env)) {
    if (env[key] === undefined) delete process.env[key];
    else process.env[key] = env[key]!;
  }
  try {
    fn();
  } finally {
    process.env = prev;
  }
}

const GITHUB_CI_ENV = {
  CI: "true",
  TEST_ENVIRONMENT: "true",
  APP_ENV: "test",
  ALLOW_TEST_FIXTURES: "true",
  EXPECTED_TEST_PROJECT_REF: "kmmegunjvssclsjlarun",
  SUPABASE_TEST_URL: "https://kmmegunjvssclsjlarun.supabase.co",
  SUPABASE_TEST_ANON_KEY: "sb_publishable_test_value",
  SUPABASE_TEST_SERVICE_ROLE_KEY: "sb_secret_test_value",
  TEST_RUN_ID: "unit-runtime-guard",
  SUPABASE_DB_URL: "postgresql://postgres.kmmegunjvssclsjlarun@aws-0-eu-west-1.pooler.supabase.com:5432/postgres",
  DATABASE_URL: undefined,
};

describe("runtime environment guard", () => {
  it("accepts the exact GitHub CI isolated-test environment with modern keys", () => {
    withEnv(GITHUB_CI_ENV, () => {
      expect(runtimeEnvironmentConfigured()).toBe(true);
      expect(() => assertRuntimeEnvironmentConfigured()).not.toThrow();
    });
  });

  it("rejects the production project ref", () => {
    withEnv({ ...GITHUB_CI_ENV, EXPECTED_TEST_PROJECT_REF: PRODUCTION_PROJECT_REF }, () => {
      expect(runtimeEnvironmentConfigured()).toBe(false);
      expect(() => assertRuntimeEnvironmentConfigured()).toThrow(/EXPECTED_TEST_PROJECT_REF/);
    });
  });

  it("missing variables cause a hard CI failure listing only invalid variable names", () => {
    withEnv(
      {
        ...GITHUB_CI_ENV,
        SUPABASE_TEST_ANON_KEY: undefined,
        SUPABASE_TEST_SERVICE_ROLE_KEY: undefined,
      },
      () => {
        expect(() => assertRuntimeEnvironmentConfigured()).toThrow(
          /Runtime environment invalid: SUPABASE_TEST_ANON_KEY, SUPABASE_TEST_SERVICE_ROLE_KEY/,
        );
      },
    );
  });

  it("local unconfigured execution exposes a clear local-only skip reason", () => {
    withEnv({ ...GITHUB_CI_ENV, CI: undefined, TEST_ENVIRONMENT: undefined }, () => {
      const diagnostics = runtimeEnvironmentDiagnostics();
      expect(diagnostics.configured).toBe(false);
      expect(diagnostics.localSkipReason).toBe("LOCAL_RUNTIME_UNCONFIGURED: TEST_ENVIRONMENT");
    });
  });

  it("does not print API key values in diagnostics or thrown errors", () => {
    withEnv(
      {
        ...GITHUB_CI_ENV,
        SUPABASE_TEST_URL: "https://invalid.example.test",
      },
      () => {
        const diagnostics = runtimeEnvironmentDiagnostics();
        expect(diagnostics.invalidFields.join(",")).not.toContain("sb_publishable_test_value");
        expect(diagnostics.invalidFields.join(",")).not.toContain("sb_secret_test_value");

        try {
          assertRuntimeEnvironmentConfigured();
        } catch (error) {
          const message = (error as Error).message;
          expect(message).not.toContain("sb_publishable_test_value");
          expect(message).not.toContain("sb_secret_test_value");
        }
      },
    );
  });
});