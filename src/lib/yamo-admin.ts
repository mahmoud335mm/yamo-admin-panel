import { supabase } from "@/integrations/supabase/client";
import { formatDateTime, formatNumber } from "@/lib/format";

export type YamoAdminMe = {
  user_id: string;
  email?: string;
  display_name?: string;
  roles: string[];
  permissions: string[];
};

export async function getYamoAdminMe(): Promise<YamoAdminMe> {
  const { data, error } = await supabase.rpc("get_yamo_admin_me" as never);
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) throw new Error("هذا الحساب غير مصرح له بدخول لوحة يامو");
  const value = row as Record<string, unknown>;
  return {
    user_id: String(value.user_id ?? ""),
    email: value.email ? String(value.email) : undefined,
    display_name: value.display_name ? String(value.display_name) : undefined,
    roles: Array.isArray(value.roles) ? value.roles.map(String) : [],
    permissions: Array.isArray(value.permissions) ? value.permissions.map(String) : [],
  };
}

export async function yamoRows(source: string, limit = 200): Promise<Record<string, unknown>[]> {
  const { data, error } = await supabase
    .from(source as never)
    .select("*")
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as Record<string, unknown>[];
}


export type YamoAdminUserLookup = {
  id: string;
  legacy_id: string;
  display_name: string;
  avatar_url?: string | null;
  gender?: string | null;
  account_status?: string | null;
  level?: number | null;
  vip_level?: number | null;
};

/**
 * Lightweight admin-side user lookup used by grant/send dialogs.
 * Searches the permission-gated admin_profiles view by Yamo legacy ID.
 */
export async function searchYamoAdminUsers(term: string, limit = 8): Promise<YamoAdminUserLookup[]> {
  const needle = term.trim();
  if (!needle) return [];

  // admin_profiles is a Yamo compatibility view that may not be present in the
  // generated Supabase TS schema yet, so keep this isolated cast here.
  const table = supabase.from("admin_profiles" as never) as any;
  const { data, error } = await table
    .select("id,legacy_id,display_name,avatar_url,gender,account_status,level,vip_level")
    .ilike("legacy_id", `%${needle}%`)
    .order("legacy_id", { ascending: true })
    .limit(Math.max(1, Math.min(limit, 12)));

  if (error) throw error;
  return ((data ?? []) as Record<string, unknown>[])
    .map((row) => ({
      id: String(row.id ?? ""),
      legacy_id: String(row.legacy_id ?? ""),
      display_name: String(row.display_name ?? row.legacy_id ?? ""),
      avatar_url: row.avatar_url ? String(row.avatar_url) : null,
      gender: row.gender ? String(row.gender) : null,
      account_status: row.account_status ? String(row.account_status) : null,
      level: row.level == null ? null : Number(row.level),
      vip_level: row.vip_level == null ? null : Number(row.vip_level),
    }))
    .filter((row) => row.id && row.legacy_id);
}

export async function yamoRpc<T = unknown>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await supabase.rpc(name as never, args as never);
  if (error) throw error;
  return data as T;
}

export function readableValue(value: unknown): string {
  if (value == null) return "—";
  if (typeof value === "boolean") return value ? "نعم" : "لا";
  if (typeof value === "object") return JSON.stringify(value);
  if (typeof value === "number") return formatNumber(value);
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}T/.test(value)) {
    return formatDateTime(value);
  }
  return String(value);
}
