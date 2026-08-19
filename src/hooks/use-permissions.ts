import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { getYamoAdminMe } from "@/lib/yamo-admin";

export type AdminRole =
  | "super_admin"
  | "admin"
  | "finance"
  | "moderator"
  | "rooms_manager"
  | "agency_manager"
  | "bd_manager"
  | "support"
  | "auditor"
  | "viewer"
  | "content_manager";

const permissionAliases: Record<string, string[]> = {
  "dashboard.view": ["users.read", "economy.read", "audit.read"],
  "users.view": ["users.read"],
  "economy.view": ["economy.read"],
  "rooms.read": ["rooms.manage"],
  "messages.read": ["content.moderate"],
  "posts.read": ["content.moderate"],
  "gifts.read": ["catalog.manage"],
  "games.read": ["games.manage"],
  "events.read": ["events.manage"],
  "banners.read": ["banners.manage", "settings.manage"],
  "daily_login.read": ["settings.manage"],
  "users.moderate": [
    "users.suspend",
    "users.ban",
    "users.warn",
    "users.room_ban",
    "users.message_ban",
    "users.post_ban",
    "users.call_ban",
  ],
  "notifications.read": [
    "notifications.send",
    "notifications.events_send",
    "notifications.marketing_send",
    "notifications.system_send",
  ],
  "reports.read": ["content.moderate"],
  "analytics.read": ["audit.read"],
  "settings.read": ["settings.manage"],
  "admin.users.read": ["admins.manage"],
  "admin.users.write": ["admins.manage"],
};

export function usePermissions() {
  const q = useQuery({
    queryKey: ["me", "permissions"],
    queryFn: async () => {
      const [admin, me] = await Promise.all([getYamoAdminMe(), supabase.auth.getUser()]);
      return {
        permissions: new Set(admin.permissions),
        roles: admin.roles as AdminRole[],
        user: me.data.user,
      };
    },
    staleTime: 60_000,
  });

  const has = (perm: string) => {
    if (q.data?.roles.includes("super_admin")) return true;
    if (q.data?.permissions.has(perm)) return true;
    return (permissionAliases[perm] ?? []).some((alias) => q.data?.permissions.has(alias)) || false;
  };
  const hasAny = (perms: string[]) => perms.some(has);
  const hasRole = (r: AdminRole) => q.data?.roles.includes(r) ?? false;
  return { ...q, has, hasAny, hasRole, roles: q.data?.roles ?? [], user: q.data?.user };
}
