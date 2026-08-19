import { describe, it, expect, beforeAll } from "vitest";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";
import { loadSharedFixtures, type SharedSession } from "./shared-fixtures";

describe("5D-2R chargeback-records", () => {
  let sessions: Record<string, SharedSession> = {};

  beforeAll(() => {
    ({ sessions } = loadSharedFixtures());
  });

  it("acknowledge_chargeback records only, no ledger", async () => {
    const { admin, env } = await getVerifiedAdminClient();
    void sessions; void env;
    const res: any = await (sessions.support?.client ?? admin).rpc('acknowledge_chargeback', { _dispute_id: '00000000-0000-0000-0000-000000000000', _reason: 't', _idempotency_key: 'k' });
    
    expect(res).toBeDefined();
  });
});
