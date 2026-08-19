import { describe, it, expect } from "vitest";
import { redactSensitiveData } from "@/lib/redact.server";

describe("redactSensitiveData", () => {
  it("redacts secret keys entirely", () => {
    const out = redactSensitiveData({
      authorization: "Bearer abc.def.ghi",
      api_key: "sk_live_xyz",
      client_secret: "top",
      password: "pw",
      pin: "1234",
      cvv: "123",
    }) as Record<string, string>;
    for (const k of Object.keys(out)) {
      expect(out[k]).toBe("***REDACTED***");
    }
  });

  it("masks PII fields", () => {
    const out = redactSensitiveData({
      account_number: "SA0380000000608010167519",
      phone: "+966501234567",
      email: "user@example.com",
      iban: "DE89370400440532013000",
    }) as Record<string, string>;
    for (const k of Object.keys(out)) {
      expect(out[k]).not.toContain("example.com");
      expect(out[k]).not.toBe("+966501234567");
      expect(out[k]).not.toBe("DE89370400440532013000");
    }
  });

  it("scrubs Bearer and JWT patterns inside free text", () => {
    const out = redactSensitiveData({
      note: "auth Bearer eyJhbGciOi.eyJzdWIiOi.SflKxwRJSMe here",
    }) as { note: string };
    expect(out.note).toContain("Bearer ***");
    expect(out.note).not.toContain("eyJhbGciOi.eyJzdWIiOi.SflKxwRJSMe");
  });

  it("masks card-like sequences", () => {
    const out = redactSensitiveData({ msg: "card 4111 1111 1111 1111 ok" }) as { msg: string };
    expect(out.msg).not.toContain("4111 1111 1111 1111");
    expect(out.msg).toMatch(/••••••/);
  });

  it("handles nested objects and arrays", () => {
    const out = redactSensitiveData({
      inner: { list: [{ password: "x", email: "a@b.c" }, { api_key: "k" }] },
    }) as any;
    expect(out.inner.list[0].password).toBe("***REDACTED***");
    expect(out.inner.list[1].api_key).toBe("***REDACTED***");
  });

  it("caps depth without throwing", () => {
    let d: any = { v: 1 };
    for (let i = 0; i < 20; i++) d = { child: d };
    expect(() => redactSensitiveData(d)).not.toThrow();
  });

  it("ignores prototype pollution keys", () => {
    const input = JSON.parse('{"__proto__":{"polluted":true},"safe":"ok"}');
    const out = redactSensitiveData(input) as any;
    expect(({} as any).polluted).toBeUndefined();
    expect(out.safe).toBe("ok");
  });

  it("truncates long arrays", () => {
    const arr = Array.from({ length: 200 }, (_, i) => i);
    const out = redactSensitiveData(arr) as unknown[];
    expect(out.length).toBeLessThanOrEqual(101);
    expect(String(out[out.length - 1])).toContain("truncated");
  });
});
