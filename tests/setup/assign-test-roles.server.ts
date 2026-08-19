/**
 * Phase 5D-2R: assigns RBAC roles to provisioned harness users.
 */
import { getVerifiedAdminClient } from "./verified-admin-client.server";
import type { ProvisionedUser } from "./create-test-users.server";

export async function assignTestRoles(users: ProvisionedUser[]): Promise<void> {
  const { admin } = await getVerifiedAdminClient();
  for (const u of users) {
    if (!u.role) continue;
    const { error: adminUserError } = await admin.from("admin_users").insert({
      id: u.id,
      email: u.email,
      full_name: u.handle,
      is_active: true,
    });
    if (adminUserError && !adminUserError.message.includes("duplicate")) {
      throw new Error(`assignAdminUser(${u.handle}) failed: ${adminUserError.message}`);
    }

    const { error } = await admin.from("admin_role_assignments").insert({
      admin_user_id: u.id,
      role: u.role,
    });
    if (error && !error.message.includes("duplicate")) {
      throw new Error(`assignRole(${u.role}) failed: ${error.message}`);
    }
  }
}
