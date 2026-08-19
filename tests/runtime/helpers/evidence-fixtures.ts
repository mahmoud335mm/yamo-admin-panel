/**
 * Phase 5D-2R evidence fixtures.
 * Small in-repo files (safe MIME) and runtime-generated oversized/blocked
 * fixtures. Everything tagged with test_run_id so cleanup is scoped.
 */
export interface EvidenceFixture {
  name: string;
  contentType: string;
  bytes: Uint8Array;
  expectedQuarantined: boolean;
}

const enc = (s: string) => new TextEncoder().encode(s);

export function safeFixtures(): EvidenceFixture[] {
  return [
    { name: "sample.txt", contentType: "text/plain",       bytes: enc("hello"),         expectedQuarantined: false },
    { name: "sample.eml", contentType: "message/rfc822",   bytes: enc("From: t@t\n"),   expectedQuarantined: false },
    { name: "sample.pdf", contentType: "application/pdf",  bytes: enc("%PDF-1.4\n%%EOF"), expectedQuarantined: false },
    { name: "sample.jpg", contentType: "image/jpeg",       bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), expectedQuarantined: false },
  ];
}

export function blockedFixtures(): EvidenceFixture[] {
  return [
    { name: "blocked.svg",  contentType: "image/svg+xml",         bytes: enc("<svg/>"),   expectedQuarantined: true },
    { name: "blocked.html", contentType: "text/html",             bytes: enc("<html/>"),  expectedQuarantined: true },
    { name: "blocked.js",   contentType: "application/javascript", bytes: enc("alert(1)"), expectedQuarantined: true },
  ];
}

export function oversizedFixture(bytes = 26 * 1024 * 1024): EvidenceFixture {
  return {
    name: "oversized.bin",
    contentType: "application/octet-stream",
    bytes: new Uint8Array(bytes),
    expectedQuarantined: true,
  };
}
