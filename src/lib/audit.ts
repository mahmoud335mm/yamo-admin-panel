import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

type Json = Database["public"]["Tables"]["audit_logs"]["Insert"]["metadata"];

export async function logAudit(action: string, entityType?: string, entityId?: string, metadata: Record<string, unknown> = {}) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  await supabase.from("audit_logs").insert({
    actor_id: user.id,
    actor_email: user.email,
    action,
    entity_type: entityType,
    entity_id: entityId,
    metadata: metadata as Json,
    user_agent: typeof navigator !== "undefined" ? navigator.userAgent : null,
  });
}
