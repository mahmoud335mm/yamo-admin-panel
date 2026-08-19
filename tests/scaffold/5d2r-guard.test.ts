/**
 * Phase 5D-2R scaffold validation.
 * These tests do NOT hit any database. They verify the guard and scaffold
 * files themselves fail closed and never contain secrets.
 */
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";
import {
  assertRuntimeEnvironmentConfigured,
  assertTestEnvironment,
  GuardError,
  PRODUCTION_PROJECT_REF,
  runtimeEnvironmentConfigured,
  runtimeEnvironmentDiagnostics,
} from "../setup/_guard.server";

function withEnv(env: Record<string, string | undefined>, fn: () => void) {
  const prev = { ...process.env };
  for (const k of Object.keys(env)) {
    if (env[k] === undefined) delete process.env[k];
    else process.env[k] = env[k]!;
  }
  try { fn(); } finally { process.env = prev; }
}

const VALID = {
  TEST_ENVIRONMENT: "true",
  APP_ENV: "test",
  ALLOW_TEST_FIXTURES: "true",
  SUPABASE_TEST_URL: "https://kmmegunjvssclsjlarun.supabase.co",
  SUPABASE_TEST_ANON_KEY: "sb_publishable_test",
  SUPABASE_TEST_SERVICE_ROLE_KEY: "sb_secret_test",
  EXPECTED_TEST_PROJECT_REF: "kmmegunjvssclsjlarun",
  TEST_RUN_ID: "run-1",
  SUPABASE_DB_URL: "postgresql://postgres.kmmegunjvssclsjlarun@aws-0-eu-west-1.pooler.supabase.com:5432/postgres",
  DATABASE_URL: undefined,
};

describe("5D-2R scaffold guard", () => {
  it("passes with a valid isolated Test project env", () => {
    withEnv(VALID, () => expect(() => assertTestEnvironment()).not.toThrow());
  });

  it("runtimeEnvironmentConfigured accepts modern publishable and secret key formats", () => {
    withEnv(
      {
        ...VALID,
        SUPABASE_TEST_ANON_KEY: "sb_publishable_test_value",
        SUPABASE_TEST_SERVICE_ROLE_KEY: "sb_secret_test_value",
      },
      () => expect(runtimeEnvironmentConfigured()).toBe(true),
    );
  });

  it("production ref is rejected by the canonical runtime helper", () => {
    withEnv({ ...VALID, EXPECTED_TEST_PROJECT_REF: PRODUCTION_PROJECT_REF }, () => {
      expect(runtimeEnvironmentConfigured()).toBe(false);
      expect(() => assertRuntimeEnvironmentConfigured()).toThrow(/EXPECTED_TEST_PROJECT_REF/);
    });
  });

  it("missing variables cause a hard CI failure listing names only", () => {
    withEnv(
      {
        ...VALID,
        CI: "true",
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

  it("local unconfigured execution exposes one local-only skip reason", () => {
    withEnv({ ...VALID, CI: undefined, SUPABASE_TEST_URL: undefined }, () => {
      const diagnostics = runtimeEnvironmentDiagnostics();
      expect(diagnostics.configured).toBe(false);
      expect(diagnostics.localSkipReason).toMatch(/^LOCAL_RUNTIME_UNCONFIGURED:/);
      expect(diagnostics.invalidFields).toContain("SUPABASE_TEST_URL");
    });
  });

  it("canonical runtime helper never prints API key values", () => {
    withEnv(
      {
        ...VALID,
        CI: "true",
        SUPABASE_TEST_URL: "https://invalid.example.test",
        SUPABASE_TEST_ANON_KEY: "sb_publishable_test_value",
        SUPABASE_TEST_SERVICE_ROLE_KEY: "sb_secret_test_value",
      },
      () => {
        try { assertRuntimeEnvironmentConfigured(); }
        catch (e) {
          const message = (e as Error).message;
          expect(message).not.toContain("sb_publishable_test_value");
          expect(message).not.toContain("sb_secret_test_value");
        }
      },
    );
  });

  it("rejects when TEST_ENVIRONMENT is not 'true'", () => {
    withEnv({ ...VALID, TEST_ENVIRONMENT: "false" }, () => {
      expect(() => assertTestEnvironment()).toThrow(/TEST_ENVIRONMENT_INVALID/);
    });
  });

  it("rejects when APP_ENV is not 'test'", () => {
    withEnv({ ...VALID, APP_ENV: "production" }, () => {
      expect(() => assertTestEnvironment()).toThrow(/TEST_ENVIRONMENT_INVALID/);
    });
  });

  it("rejects when ALLOW_TEST_FIXTURES is missing", () => {
    withEnv({ ...VALID, ALLOW_TEST_FIXTURES: undefined }, () => {
      expect(() => assertTestEnvironment()).toThrow(/TEST_FIXTURES_DISABLED/);
    });
  });

  it("rejects production URL", () => {
    withEnv({ ...VALID, SUPABASE_TEST_URL: `https://${PRODUCTION_PROJECT_REF}.supabase.co` }, () => {
      expect(() => assertTestEnvironment()).toThrow(/PRODUCTION_PROJECT_BLOCKED/);
    });
  });

  it("rejects production project ref", () => {
    withEnv({ ...VALID, EXPECTED_TEST_PROJECT_REF: PRODUCTION_PROJECT_REF }, () => {
      expect(() => assertTestEnvironment()).toThrow(/PRODUCTION_PROJECT_BLOCKED/);
    });
  });

  it("rejects ref mismatch between URL and EXPECTED_TEST_PROJECT_REF", () => {
    withEnv({ ...VALID, EXPECTED_TEST_PROJECT_REF: "otherref" }, () => {
      expect(() => assertTestEnvironment()).toThrow(/TEST_PROJECT_REF_MISMATCH/);
    });
  });

  it("rejects missing service role key", () => {
    withEnv({ ...VALID, SUPABASE_TEST_SERVICE_ROLE_KEY: undefined }, () => {
      expect(() => assertTestEnvironment()).toThrow(/TEST_SERVICE_ROLE_MISSING/);
    });
  });

  it("rejects missing anon key", () => {
    withEnv({ ...VALID, SUPABASE_TEST_ANON_KEY: undefined }, () => {
      expect(() => assertTestEnvironment()).toThrow(/TEST_ANON_KEY_MISSING/);
    });
  });

  it("never includes the service role in the thrown error message", () => {
    withEnv({ ...VALID, SUPABASE_TEST_URL: `https://${PRODUCTION_PROJECT_REF}.supabase.co` }, () => {
      try { assertTestEnvironment(); }
      catch (e) {
        expect((e as GuardError).message).not.toContain(VALID.SUPABASE_TEST_SERVICE_ROLE_KEY);
      }
    });
  });
});

describe("5D-2R scaffold hygiene", () => {
  const specDir = join(process.cwd(), "tests/runtime/5d2");
  const specs = readdirSync(specDir).filter((f) => f.endsWith(".spec.ts"));

  it("has runtime specs", () => {
    expect(specs.length).toBeGreaterThanOrEqual(13);
  });

  it("no it.todo in 5D-2R runtime specs", () => {
    for (const f of specs) {
      const src = readFileSync(join(specDir, f), "utf8");
      expect(src, `${f} must not contain it.todo`).not.toMatch(/\bit\.todo\b/);
    }
  });

  it("5D-2R runtime specs do not register blocked or conditional suites", () => {
    const forbiddenRuntimeSkipTokens = [
      "describe.runIf",
      "describe.skipIf",
      "test.runIf",
      "test.skipIf",
      "it.runIf",
      "it.skipIf",
      "(blocked)",
      "BLOCKED_PENDING_TEST_PROJECT",
      "runtimeAvailable",
      "skipReason",
    ];

    for (const f of specs) {
      const src = readFileSync(join(specDir, f), "utf8");
      for (const token of forbiddenRuntimeSkipTokens) {
        expect(src, `${f} must not contain ${token}`).not.toContain(token);
      }
    }
  });

  it("5D-2R runtime specs load the shared global fixtures", () => {
    for (const f of specs) {
      const src = readFileSync(join(specDir, f), "utf8");
      expect(src, `${f} must load shared fixtures`).toContain(
        'from "./shared-fixtures"',
      );
      expect(src, `${f} must call loadSharedFixtures()`).toMatch(/loadSharedFixtures\(\)/);
    }
  });

  it("5D-2R runtime specs never call the per-spec provisioning helpers", () => {
    for (const f of specs) {
      const src = readFileSync(join(specDir, f), "utf8");
      expect(src, `${f} must not call provisionTestUsers`).not.toMatch(/provisionTestUsers\(/);
      expect(src, `${f} must not call assignTestRoles`).not.toMatch(/assignTestRoles\(/);
      expect(src, `${f} must not call mintAllSessions`).not.toMatch(/mintAllSessions\(/);
    }
  });

  it("Vitest runtime config wires the shared global setup for 5D-2", () => {
    const src = readFileSync(join(process.cwd(), "vitest.runtime.config.ts"), "utf8");
    expect(src).toContain('"tests/runtime/5d2/global-setup.ts"');
    expect(src).toContain("fileParallelism: false");
  });

  it("baseline v4 removes financial_resolution_status from the no-side-effects assertion", () => {
    const v4 = readFileSync(
      join(process.cwd(), "supabase/test-migrations/5d2r_baseline_snapshot_v4.sql"),
      "utf8",
    );
    expect(v4).toContain("CREATE OR REPLACE FUNCTION public.assert_5d2_no_financial_side_effects");
    expect(v4).toContain("CREATE OR REPLACE FUNCTION public.capture_5d2_baseline");
    expect(v4).not.toContain("financial_resolution_status");
    expect(v4).toContain("executed_at IS NOT NULL");
  });

  it("SQL test files carry TEST PROJECT ONLY header", () => {
    const dir = join(process.cwd(), "supabase/test-migrations");
    for (const f of readdirSync(dir).filter((x) => x.endsWith(".sql"))) {
      const src = readFileSync(join(dir, f), "utf8");
      expect(src, `${f} missing TEST PROJECT ONLY header`).toMatch(/TEST PROJECT ONLY/);
      expect(src, `${f} missing DO NOT APPLY TO PRODUCTION`).toMatch(/DO NOT APPLY TO PRODUCTION/);
    }
  });

  it("baseline snapshot references only real wallet balance schema columns", () => {
    const walletMigration = readFileSync(
      join(process.cwd(), "supabase/migrations/20260717220425_adff6fd9-448c-4820-8b30-6462a9abb45d.sql"),
      "utf8",
    );
    const walletTableMatch = walletMigration.match(/CREATE TABLE public\.wallets \(([\s\S]*?)\n\);/);
    expect(walletTableMatch, "wallets table definition must exist in migrations").not.toBeNull();
    const walletColumns = new Set(
      (walletTableMatch?.[1] ?? "")
        .split("\n")
        .map((line) => line.trim().match(/^([a-z_]+)\s/)?.[1])
        .filter(Boolean),
    );

    for (const column of ["account", "balance", "reserved"] as const) {
      expect(walletColumns.has(column), `wallets.${column} must exist`).toBe(true);
    }
    for (const missingColumn of ["coins", "pearls", "bonus_coins"] as const) {
      expect(walletColumns.has(missingColumn), `wallets.${missingColumn} must not be assumed`).toBe(false);
    }

    for (const file of ["5d2r_baseline_snapshot.sql", "5d2r_baseline_snapshot_v2.sql", "5d2r_baseline_snapshot_v3.sql", "5d2r_baseline_snapshot_v4.sql"] as const) {
      const src = readFileSync(join(process.cwd(), "supabase/test-migrations", file), "utf8");
      expect(src, `${file} must aggregate the row-based balance column`).toContain("SUM(balance)");
      expect(src, `${file} must use the wallet account discriminator`).toContain("account = 'coins'::public.wallet_account");
      expect(src, `${file} must use diamonds as the stored pearl account`).toContain("account = 'diamonds'::public.wallet_account");
      expect(src, `${file} must use the bonus account discriminator`).toContain("account = 'bonus'::public.wallet_account");
      expect(src, `${file} must not reference non-existent wallets.coins`).not.toMatch(/SUM\(coins\)/);
      expect(src, `${file} must not reference non-existent wallets.pearls`).not.toMatch(/SUM\(pearls\)/);
      expect(src, `${file} must not reference non-existent wallets.bonus_coins`).not.toMatch(/SUM\(bonus_coins\)/);
    }
  });

  it("test-only auth fixture bypass is fully marker and metadata gated", () => {
    const src = readFileSync(join(process.cwd(), "supabase/test-migrations/5d2r_auth_fixture_bypass.sql"), "utf8");
    const bypassStart = src.indexOf("IF EXISTS (");
    const bypassEnd = src.indexOf("SELECT (value)::text::boolean INTO bootstrap_enabled");
    const bypass = src.slice(bypassStart, bypassEnd);
    const productionLogic = src.slice(bypassEnd);

    expect(src).toContain("CREATE OR REPLACE FUNCTION public.handle_new_admin_user()");
    expect(bypass).toContain("environment_name = 'test'");
    expect(bypass).toContain("project_ref = 'kmmegunjvssclsjlarun'");
    expect(bypass).toContain("test_fixtures_allowed IS TRUE");
    expect(bypass).toContain("NEW.raw_user_meta_data->>'test_run_id'");
    expect(bypass).toContain("NEW.raw_user_meta_data->>'fixture_scope'");
    expect(bypass).toContain("NEW.raw_user_meta_data->>'harness_role'");
    expect(bypass.indexOf("NEW.raw_user_meta_data->>'test_run_id'")).toBeGreaterThan(-1);
    expect(bypass.indexOf("NEW.raw_user_meta_data->>'fixture_scope'")).toBeGreaterThan(
      bypass.indexOf("NEW.raw_user_meta_data->>'test_run_id'"),
    );
    expect(bypass.indexOf("NEW.raw_user_meta_data->>'harness_role'")).toBeGreaterThan(
      bypass.indexOf("NEW.raw_user_meta_data->>'fixture_scope'"),
    );
    expect(bypass).toContain("'plain_user'");
    expect(bypass).toContain("'support'");
    expect(bypass).toContain("RETURN NEW;");
    expect(bypass).not.toContain(PRODUCTION_PROJECT_REF);
    expect(productionLogic).toContain("RAISE EXCEPTION 'Admin signup is closed. An invitation is required.'");
    expect(productionLogic).toContain("INSERT INTO public.admin_users (id, email, full_name)");
    expect(productionLogic).toContain("INSERT INTO public.admin_role_assignments(admin_user_id, role) VALUES (NEW.id, 'super_admin')");
  });

  it("test fixture metadata always includes a non-empty harness_role", () => {
    const src = readFileSync(join(process.cwd(), "tests/setup/create-test-users.server.ts"), "utf8");
    expect(src).toContain('const harnessRole = role ?? "plain_user";');
    expect(src).toContain("harness_role: harnessRole");
    expect(src).not.toContain("harness_role: role");
  });

  it("baseline test-only functions reference only relations present in current migrations", () => {
    const migrationDir = join(process.cwd(), "supabase/migrations");
    const createdRelations = new Set<string>();
    for (const f of readdirSync(migrationDir).filter((x) => x.endsWith(".sql"))) {
      const src = readFileSync(join(migrationDir, f), "utf8");
      for (const match of src.matchAll(/CREATE TABLE(?: IF NOT EXISTS)? public\.([a-z_]+)/g)) {
        createdRelations.add(match[1]);
      }
    }

    for (const baselineFile of ["5d2r_baseline_snapshot_v3.sql", "5d2r_baseline_snapshot_v4.sql"] as const) {
      const src = readFileSync(join(process.cwd(), "supabase/test-migrations", baselineFile), "utf8");
      const referencedRelations = Array.from(new Set(
        Array.from(src.matchAll(/FROM public\.([a-z_]+)/g)).map((match) => match[1]),
      )).filter((table) => table !== "test_environment_marker" && table !== "test_baseline_snapshots");

      for (const relation of referencedRelations) {
        expect(createdRelations.has(relation), `${baselineFile}: ${relation} must exist in current migrations`).toBe(true);
      }
      expect(src, `${baselineFile} must not reference refund_receivables`).not.toContain("public.refund_receivables");
      expect(src, `${baselineFile} must not reference wallet_adjustments`).not.toContain("public.wallet_adjustments");
      expect(src, `${baselineFile} must not reference refund_gateway_attempts`).not.toContain("public.refund_gateway_attempts");
    }

    const v4 = readFileSync(join(process.cwd(), "supabase/test-migrations/5d2r_baseline_snapshot_v4.sql"), "utf8");
    expect(v4, "v4 must remove the invalid financial_resolution_status reference").not.toContain("financial_resolution_status");
  });

  it("CI workflow contains no literal secret values", () => {
    const src = readFileSync(join(process.cwd(), ".github/workflows/5d2-runtime-test.yml"), "utf8");
    expect(src).not.toMatch(/sb_secret_[A-Za-z0-9_-]{6,}/);
    expect(src).not.toMatch(/eyJ[A-Za-z0-9_-]{20,}/);
  });

  it("no service_role import in src/ client bundle", () => {
    // NOTE: this is a coarse sweep; the exhaustive check runs in the existing
    // G-10/G-29 secret-scan gate.
    // We only guard against accidental additions here.
    const check = (dir: string) => {
      const items = readdirSync(dir, { withFileTypes: true });
      for (const it of items) {
        const p = join(dir, it.name);
        if (it.isDirectory()) check(p);
        else if (/\.(tsx?|jsx?)$/.test(it.name) && !p.includes(".server.") && !p.includes(".functions.")) {
          const src = readFileSync(p, "utf8");
          expect(src, `${p} must not import client.server`).not.toMatch(/from ["']@\/integrations\/supabase\/client\.server["']/);
        }
      }
    };
    check(join(process.cwd(), "src"));
  });
});
