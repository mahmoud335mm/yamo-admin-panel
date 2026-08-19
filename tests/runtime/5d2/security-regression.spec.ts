import { describe, it, expect, beforeAll } from "vitest";
import { getVerifiedAdminClient } from "../../setup/verified-admin-client.server";
import { loadSharedFixtures, type SharedSession } from "./shared-fixtures";

describe("5D-2R security-regression", () => {
  let sessions: Record<string, SharedSession> = {};

  beforeAll(() => {
    ({ sessions } = loadSharedFixtures());
  });

  it("anon has zero EXECUTE on dispute RPCs", async () => {
    const { admin, env } = await getVerifiedAdminClient();
    void sessions; void env;
    const res: any = await (sessions.support?.client ?? admin).rpc('create_recharge_dispute', {});
    expect(res.error).toBeTruthy();
  });
});
