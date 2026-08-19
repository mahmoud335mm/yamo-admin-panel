/**
 * Server-only redaction utility.
 * All webhook payloads, audit metadata, and gateway responses pass through
 * this before being sent to the client.
 *
 * NEVER import this from client code — filename `.server.ts` blocks it.
 */

/* ------------------------------------------------------------------ */
/* Configuration                                                      */
/* ------------------------------------------------------------------ */

const REDACT_KEYS = new Set([
  "authorization",
  "api_key",
  "apikey",
  "x-api-key",
  "secret",
  "secret_key",
  "private_key",
  "access_token",
  "refresh_token",
  "id_token",
  "password",
  "passcode",
  "pin",
  "otp",
  "cvv",
  "cvc",
  "cvv2",
  "cookie",
  "set-cookie",
  "session",
  "session_id",
  "sessionid",
  "client_secret",
  "webhook_secret",
  "signature_secret",
  "service_role",
  "bearer",
  "sb_secret",
  "encryption_key",
]);

const MASK_KEYS = new Set([
  "card_number",
  "pan",
  "cardnumber",
  "account_number",
  "accountnumber",
  "iban",
  "wallet_number",
  "walletnumber",
  "phone",
  "phone_number",
  "mobile",
  "email",
  "email_address",
  "national_id",
  "nationalid",
  "provider_payment_id",
  "external_reference",
]);

const REDACTED = "***REDACTED***";
const MAX_STRING_LENGTH = 500;
const MAX_DEPTH = 8;
const MAX_KEYS_PER_OBJECT = 200;
const MAX_ARRAY_LENGTH = 100;

const BEARER_RE = /\bBearer\s+[A-Za-z0-9._~+/=-]{16,}\b/gi;
const JWT_RE = /\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g;
const CARD_LIKE_RE = /\b(?:\d[ -]?){13,19}\b/g;

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

function maskString(value: string, keep = 4): string {
  if (value.length <= keep * 2) return "•".repeat(Math.min(value.length, 8));
  return `${value.slice(0, keep)}${"•".repeat(6)}${value.slice(-keep)}`;
}

function scrubInlineSecrets(s: string): string {
  if (s.length > MAX_STRING_LENGTH) s = s.slice(0, MAX_STRING_LENGTH) + "…";
  let out = s.replace(BEARER_RE, "Bearer ***");
  out = out.replace(JWT_RE, "***JWT***");
  out = out.replace(CARD_LIKE_RE, (m) => {
    const digits = m.replace(/\D/g, "");
    if (digits.length < 13 || digits.length > 19) return m;
    return `${digits.slice(0, 4)}••••••${digits.slice(-4)}`;
  });
  return out;
}

/* ------------------------------------------------------------------ */
/* Core                                                               */
/* ------------------------------------------------------------------ */

export function redactSensitiveData(input: unknown, depth = 0): unknown {
  if (depth > MAX_DEPTH) return "[max-depth]";
  if (input === null || input === undefined) return input;

  const t = typeof input;
  if (t === "number" || t === "boolean" || t === "bigint") return input;
  if (t === "string") return scrubInlineSecrets(input as string);

  if (Array.isArray(input)) {
    const arr = input.slice(0, MAX_ARRAY_LENGTH);
    const truncated = input.length > MAX_ARRAY_LENGTH;
    const result: unknown[] = arr.map((v) => redactSensitiveData(v, depth + 1));
    if (truncated) result.push(`[+${input.length - MAX_ARRAY_LENGTH} truncated]`);
    return result;
  }

  if (t === "object") {
    // prototype-pollution safeguard: never traverse __proto__ / constructor
    const src = input as Record<string, unknown>;
    const keys = Object.keys(src).slice(0, MAX_KEYS_PER_OBJECT);
    const out: Record<string, unknown> = Object.create(null);
    for (const k of keys) {
      if (k === "__proto__" || k === "constructor" || k === "prototype") continue;
      const lower = k.toLowerCase();
      const v = src[k];

      if (REDACT_KEYS.has(lower)) {
        out[k] = REDACTED;
        continue;
      }
      if (MASK_KEYS.has(lower)) {
        if (typeof v === "string" && v.length > 0) out[k] = maskString(v);
        else if (typeof v === "number") out[k] = maskString(String(v));
        else out[k] = v == null ? v : REDACTED;
        continue;
      }
      out[k] = redactSensitiveData(v, depth + 1);
    }
    if (Object.keys(src).length > MAX_KEYS_PER_OBJECT) {
      out["__truncated__"] = `[+${Object.keys(src).length - MAX_KEYS_PER_OBJECT} keys]`;
    }
    // convert back to a plain object so JSON.stringify serializes normally
    return { ...out };
  }

  // functions, symbols, class instances → drop
  return null;
}

/**
 * Escape CSV formula injection.
 * Any cell value starting with = + - @ (or tab/CR) gets a leading apostrophe.
 */
export function csvSafeCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  let s = String(value);
  s = s.replace(/[\r\n]+/g, " ");
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  if (s.includes(",") || s.includes('"')) {
    s = '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

export function toCsv(headers: string[], rows: (string | number | null | undefined)[][]): string {
  const lines: string[] = [];
  lines.push(headers.map((h) => csvSafeCell(h)).join(","));
  for (const row of rows) lines.push(row.map((c) => csvSafeCell(c)).join(","));
  // BOM for Excel UTF-8 compatibility
  return "\uFEFF" + lines.join("\n");
}
