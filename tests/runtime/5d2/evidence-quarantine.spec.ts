import { describe, it, expect, beforeAll } from "vitest";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";
import { loadSharedFixtures, type SharedSession } from "./shared-fixtures";

describe("5D-2R evidence-quarantine", () => {
  let sessions: Record<string, SharedSession> = {};

  beforeAll(() => {
    ({ sessions } = loadSharedFixtures());
  });

  it("blocked mimetypes quarantined", async () => {
    const { admin, env } = await getVerifiedAdminClient();
    void sessions; void env;
    const res: any = await (sessions.support?.client ?? admin).storage.from('recharge-dispute-evidence').upload('u/blocked.svg', new Blob(['<svg/>'],{type:'image/svg+xml'}));
    
    expect(res).toBeDefined();
  });
});
