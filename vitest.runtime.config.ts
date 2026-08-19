/**
 * Vitest config for the Phase 5D-2R runtime suite ONLY.
 *
 * Runs against the isolated Supabase Test project (guard fails closed on
 * misconfiguration). Uses a single global setup so that harness users
 * are provisioned and signed-in exactly once per full invocation.
 */
import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

export default defineConfig({
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
  test: {
    include: ["tests/runtime/5d2/**/*.spec.ts"],
    globalSetup: ["tests/runtime/5d2/global-setup.ts"],
    fileParallelism: false,
    maxWorkers: 1,
    minWorkers: 1,
    hookTimeout: 120_000,
    testTimeout: 60_000,
    reporters: ["default", "json"],
    outputFile: { json: "runtime-report.json" },
  },
});
