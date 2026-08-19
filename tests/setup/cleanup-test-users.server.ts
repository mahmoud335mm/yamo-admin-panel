/**
 * Phase 5D-2R: cleanup harness users tagged with the current TEST_RUN_ID.
 * Refuses to run without a valid test marker.
 */
import { getVerifiedAdminClient } from "./verified-admin-client.server";
import { formatSafeAuthError } from "./safe-auth-error.server";

interface CleanupTestUsersOptions {
  silent?: boolean;
}

export async function cleanupTestUsers(options: CleanupTestUsersOptions = {}): Promise<{ deleted: number }> {
  const { admin, env } = await getVerifiedAdminClient();
  let deleted = 0;

  const deleteFrom = async (table: string, column: string, values: string[]): Promise<void> => {
    if (values.length === 0) return;
    const { error } = await admin.from(table).delete().in(column, values);
    if (error) throw new Error(`cleanupDelete(${table}.${column}) failed: ${error.message}`);
  };

  const deleteByTestRunMetadata = async (table: string): Promise<void> => {
    const { error } = await admin
      .from(table)
      .delete()
      .filter("metadata->>test_run_id", "eq", env.testRunId);
    if (error) throw new Error(`cleanupDelete(${table}.metadata.test_run_id) failed: ${error.message}`);
  };

  const selectIdsByTestRunMetadata = async (table: string): Promise<string[]> => {
    const { data, error } = await admin
      .from(table)
      .select("id")
      .filter("metadata->>test_run_id", "eq", env.testRunId);
    if (error) throw new Error(`cleanupSelect(${table}.metadata.test_run_id) failed: ${error.message}`);
    return ((data ?? []) as Array<{ id: string }>).map((row) => row.id);
  };

  const deleteFixtureRows = async (userIds: string[]): Promise<void> => {
    if (userIds.length === 0) return;

    const rechargeRequestIds = await selectIdsByTestRunMetadata("recharge_requests");
    const withdrawalRequestIds = await selectIdsByTestRunMetadata("withdrawal_requests");

    if (rechargeRequestIds.length > 0) {
      const { data: disputeRows, error: disputeError } = await admin
        .from("recharge_disputes")
        .select("id")
        .in("request_id", rechargeRequestIds);
      if (disputeError) throw new Error(`cleanupSelect(recharge_disputes.request_id) failed: ${disputeError.message}`);
      const disputeIds = ((disputeRows ?? []) as Array<{ id: string }>).map((row) => row.id);

      if (disputeIds.length > 0) {
        await deleteFrom("dispute_action_idempotency", "dispute_id", disputeIds);
        await deleteFrom("recharge_dispute_evidence", "dispute_id", disputeIds);
        await deleteFrom("recharge_dispute_notes", "dispute_id", disputeIds);
        await deleteFrom("recharge_disputes", "id", disputeIds);
      }

      const { data: refundRows, error: refundError } = await admin
        .from("recharge_refunds")
        .select("id")
        .in("request_id", rechargeRequestIds);
      if (refundError) throw new Error(`cleanupSelect(recharge_refunds.request_id) failed: ${refundError.message}`);
      const refundIds = ((refundRows ?? []) as Array<{ id: string }>).map((row) => row.id);
      await deleteFrom("recharge_refund_attempts", "refund_id", refundIds);
      await deleteFrom("recharge_refunds", "id", refundIds);

      await deleteFrom("recharge_receipts", "request_id", rechargeRequestIds);
      await deleteFrom("recharge_request_events", "request_id", rechargeRequestIds);
      await deleteFrom("recharge_requests", "id", rechargeRequestIds);
    }

    if (withdrawalRequestIds.length > 0) {
      await deleteFrom("withdrawal_reviews", "request_id", withdrawalRequestIds);
      await deleteFrom("withdrawal_events", "request_id", withdrawalRequestIds);
      await deleteFrom("withdrawal_requests", "id", withdrawalRequestIds);
    }

    await deleteByTestRunMetadata("recharge_refunds");
    await deleteFrom("admin_role_assignments", "admin_user_id", userIds);
    await deleteFrom("admin_role_assignments", "granted_by", userIds);
    await deleteFrom("admin_notes", "author_id", userIds);
    await deleteFrom("recharge_refund_attempts", "triggered_by", userIds);
    await deleteFrom("audit_logs", "actor_id", userIds);
    await deleteFrom("admin_users", "id", userIds);
    await deleteFrom("profiles", "id", userIds);
  };

  const perPage = 100;
  while (true) {
    const usersToDelete: string[] = [];
    for (let page = 1; ; page++) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
      if (error) throw new Error(`cleanupListUsers failed: ${formatSafeAuthError(error)}`);

      const users = data?.users ?? [];
      for (const u of users) {
        if ((u.user_metadata as { test_run_id?: string } | null)?.test_run_id === env.testRunId) {
          usersToDelete.push(u.id);
        }
      }
      if (users.length < perPage) break;
    }

    if (usersToDelete.length === 0) break;

    await deleteFixtureRows(usersToDelete);

    for (const userId of usersToDelete) {
      const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
      if (deleteError) throw new Error(`cleanupDeleteUser failed: ${formatSafeAuthError(deleteError)}`);
      deleted++;
    }
  }

  if (!options.silent) console.log(JSON.stringify({ users_deleted: deleted }));
  return { deleted };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  cleanupTestUsers().catch((err) => {
    console.error("HARNESS FAILED:", (err as Error).message);
    process.exit(1);
  });
}
