/**
 * Safe CI diagnostic for Phase 5D-2R runtime configuration.
 * Prints only readiness and invalid field names. Never prints values.
 */
import { runtimeEnvironmentDiagnostics } from "../setup/_guard.server";

const diagnostics = runtimeEnvironmentDiagnostics();

if (diagnostics.configured) {
  // eslint-disable-next-line no-console
  console.log("runtime configuration: READY");
  process.exit(0);
}

// eslint-disable-next-line no-console
console.log(`runtime configuration: INVALID (${diagnostics.invalidFields.join(", ")})`);

if (process.env.CI === "true") {
  process.exit(1);
}