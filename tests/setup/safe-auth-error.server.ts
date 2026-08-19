/**
 * Safe formatter for Auth admin errors.
 * Only emits approved primitive fields and never serializes requests,
 * headers, credentials, tokens, passwords, or connection strings.
 */
export interface SafeAuthErrorDetails {
  name?: string;
  message?: string;
  status?: number;
  code?: string;
  __isAuthError?: boolean;
}

function readAuthErrorField(error: unknown, key: keyof SafeAuthErrorDetails): unknown {
  if (!error || typeof error !== "object") return undefined;
  return (error as Record<string, unknown>)[key];
}

export function safeAuthErrorDetails(error: unknown): SafeAuthErrorDetails {
  const details: SafeAuthErrorDetails = {};
  const name = readAuthErrorField(error, "name");
  const message = readAuthErrorField(error, "message");
  const status = readAuthErrorField(error, "status");
  const code = readAuthErrorField(error, "code");
  const isAuthError = readAuthErrorField(error, "__isAuthError");

  if (typeof name === "string") details.name = name;
  if (typeof message === "string") details.message = message;
  if (typeof status === "number") details.status = status;
  if (typeof code === "string") details.code = code;
  if (typeof isAuthError === "boolean") details.__isAuthError = isAuthError;

  if (Object.keys(details).length === 0) {
    details.message = "Unknown Auth admin error";
  }
  return details;
}

export function formatSafeAuthError(error: unknown): string {
  return JSON.stringify(safeAuthErrorDetails(error));
}