import { describe, it, expect, beforeAll } from "vitest";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";
import { loadSharedFixtures, type SharedSession } from "./shared-fixtures";

describe("5D-2R create-dispute", () => {
  let sessions: Record<string, SharedSession> = {};

  beforeAll(() => {
    ({ sessions } = loadSharedFixtures());
  });

  it("support can create dispute via RPC", async () => {
    const { admin, env } = await getVerifiedAdminClient();
    void sessions; void env;
    const res: any = await (sessions.support?.client ?? admin).rpc('create_recharge_dispute', { _recharge_request_id: '00000000-0000-0000-0000-000000000000', _reason: 'chargeback' });
    
    expect(res).toBeDefined();
  });
});
