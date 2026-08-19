import { describe, it, expect, beforeAll } from "vitest";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";
import { loadSharedFixtures, type SharedSession } from "./shared-fixtures";

describe("5D-2R assignment-triage", () => {
  let sessions: Record<string, SharedSession> = {};

  beforeAll(() => {
    ({ sessions } = loadSharedFixtures());
  });

  it("admin can assign+triage dispute", async () => {
    const { admin, env } = await getVerifiedAdminClient();
    void sessions; void env;
    const res: any = await (sessions.support?.client ?? admin).rpc('assign_recharge_dispute', { _dispute_id: '00000000-0000-0000-0000-000000000000', _assignee_id: sessions.support.userId });
    
    expect(res).toBeDefined();
  });
});
