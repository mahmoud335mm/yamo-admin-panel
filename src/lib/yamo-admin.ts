import { supabase } from "@/integrations/supabase/client";

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
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}T/.test(value)) {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) return date.toLocaleString("ar-EG");
  }
  return String(value);
}
