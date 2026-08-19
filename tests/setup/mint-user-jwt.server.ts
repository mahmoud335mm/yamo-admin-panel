// Alias retained for compatibility with earlier scaffold docs.
// The real implementation lives in mint-test-sessions.server.ts and uses
// signInWithPassword — NOT admin.auth.admin.generateLink.
export { mintUserJwt, mintAllSessions, type UserSession } from "./mint-test-sessions.server";
