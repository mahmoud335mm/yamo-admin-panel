import { useEffect, useMemo, useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Loader2, Shield, ShieldOff, Undo2 } from "lucide-react";
import { toast } from "sonner";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { yamoRows, yamoRpc } from "@/lib/yamo-admin";

export const Route = createFileRoute("/_authenticated/admins")({
  component: AdminsPage,
});

function AdminsPage() {
  return (
    <div className="space-y-5">
      <YamoCommandCard
        title="منح أو سحب دور إداري"
        description="الدور يعطي مجموعة جاهزة، ويمكن تخصيص كل صلاحية تحته من القسم التالي"
        rpc="admin_assign_yamo_role"
        refreshSource="admin_users_view"
        refreshSources={["admin_user_permissions"]}
        fields={[
          { key: "user", label: "UUID المسؤول", required: true },
          { key: "role", label: "الدور", initial: "moderator", required: true },
          { key: "grant", label: "منح الدور – ألغِ العلامة للسحب", type: "checkbox" },
        ]}
        buildArgs={(v) => ({ p_user_id: v.user, p_role: v.role, p_grant: v.grant })}
      />
      <GranularPermissions />
      <YamoDataModule
        title="مسؤولو اللوحة"
        description="الحسابات الإدارية الفعلية وحالتها وأدوارها"
        source="admin_users_view"
        columns={[
          { key: "id", label: "المعرف" },
          { key: "email", label: "البريد" },
          { key: "full_name", label: "الاسم" },
          { key: "roles", label: "الأدوار" },
          { key: "is_active", label: "نشط" },
          { key: "created_at", label: "الإنشاء" },
        ]}
        actions={[
          {
            label: "تفعيل",
            rpc: "admin_set_admin_active",
            buildArgs: (r) => ({ p_user_id: r.id, p_active: true }),
          },
          {
            label: "تعطيل",
            rpc: "admin_set_admin_active",
            tone: "destructive",
            buildArgs: (r) => ({ p_user_id: r.id, p_active: false }),
          },
        ]}
      />
    </div>
  );
}

type PermissionRow = {
  user_id: string;
  email: string;
  permission: string;
  label_ar: string;
  category: string;
  role_granted: boolean;
  override_effect: "grant" | "deny" | null;
  effective: boolean;
};

function GranularPermissions() {
  const client = useQueryClient();
  const [selected, setSelected] = useState("");
  const admins = useQuery({
    queryKey: ["yamo-admin", "admin_users_view"],
    queryFn: () => yamoRows("admin_users_view", 500),
  });
  const permissions = useQuery({
    queryKey: ["yamo-admin", "admin_user_permissions"],
    queryFn: () => yamoRows("admin_user_permissions", 5000) as Promise<PermissionRow[]>,
  });
  useEffect(() => {
    if (!selected && admins.data?.[0]?.id) setSelected(String(admins.data[0].id));
  }, [admins.data, selected]);
  const rows = useMemo(
    () => (permissions.data ?? []).filter((row) => row.user_id === selected),
    [permissions.data, selected],
  );
  const groups = useMemo(
    () =>
      Object.entries(
        rows.reduce<Record<string, PermissionRow[]>>((all, row) => {
          (all[row.category] ??= []).push(row);
          return all;
        }, {}),
      ),
    [rows],
  );
  const setPermission = useMutation({
    mutationFn: ({
      permission,
      effect,
    }: {
      permission: string;
      effect: "grant" | "deny" | "inherit";
    }) =>
      yamoRpc("admin_set_yamo_permission_override", {
        p_user_id: selected,
        p_permission: permission,
        p_effect: effect,
      }),
    onSuccess: async () => {
      toast.success("تم تحديث الصلاحية وتسجيل العملية");
      await client.invalidateQueries({ queryKey: ["yamo-admin", "admin_user_permissions"] });
      await client.invalidateQueries({ queryKey: ["me", "permissions"] });
    },
    onError: (error: Error) => toast.error(error.message),
  });
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Shield className="h-5 w-5 text-primary" /> الصلاحيات الدقيقة لكل مسؤول
        </CardTitle>
        <CardDescription>
          السماح أو المنع هنا يتغلب على صلاحيات الدور؛ اختر «حسب الدور» لإلغاء التخصيص.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        <div className="flex flex-wrap items-center gap-3 rounded-xl border bg-muted/30 p-3">
          <label className="text-sm font-medium">اختر المسؤول</label>
          <select
            value={selected}
            onChange={(e) => setSelected(e.target.value)}
            className="h-10 min-w-72 rounded-md border bg-background px-3 text-sm"
          >
            {(admins.data ?? []).map((admin) => (
              <option key={String(admin.id)} value={String(admin.id)}>
                {String(admin.full_name ?? admin.email ?? admin.id)}
              </option>
            ))}
          </select>
          <Badge variant="outline">{rows.filter((r) => r.effective).length} صلاحية فعالة</Badge>
        </div>
        {permissions.isLoading ? (
          <div className="grid h-32 place-items-center">
            <Loader2 className="animate-spin" />
          </div>
        ) : (
          groups.map(([category, items]) => (
            <section key={category} className="rounded-xl border p-4">
              <h3 className="mb-3 font-bold">{categoryLabel(category)}</h3>
              <div className="grid gap-3 xl:grid-cols-2">
                {items.map((item) => (
                  <div
                    key={item.permission}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-muted/35 p-3"
                  >
                    <div>
                      <div className="text-sm font-medium">{item.label_ar}</div>
                      <div className="mt-0.5 text-xs text-muted-foreground">
                        {item.permission} · {item.effective ? "مسموح حاليًا" : "غير مسموح"}
                      </div>
                    </div>
                    <div className="flex gap-1">
                      <PermissionButton
                        active={item.override_effect === "grant"}
                        label="سماح"
                        icon={Check}
                        onClick={() =>
                          setPermission.mutate({ permission: item.permission, effect: "grant" })
                        }
                      />
                      <PermissionButton
                        active={item.override_effect === "deny"}
                        destructive
                        label="منع"
                        icon={ShieldOff}
                        onClick={() =>
                          setPermission.mutate({ permission: item.permission, effect: "deny" })
                        }
                      />
                      <PermissionButton
                        active={item.override_effect == null}
                        label="حسب الدور"
                        icon={Undo2}
                        onClick={() =>
                          setPermission.mutate({ permission: item.permission, effect: "inherit" })
                        }
                      />
                    </div>
                  </div>
                ))}
              </div>
            </section>
          ))
        )}
      </CardContent>
    </Card>
  );
}

function PermissionButton({
  active,
  destructive = false,
  label,
  icon: Icon,
  onClick,
}: {
  active: boolean;
  destructive?: boolean;
  label: string;
  icon: typeof Check;
  onClick: () => void;
}) {
  return (
    <Button
      type="button"
      size="sm"
      variant={active ? (destructive ? "destructive" : "default") : "outline"}
      onClick={onClick}
    >
      <Icon className="ml-1 h-3.5 w-3.5" />
      {label}
    </Button>
  );
}

function categoryLabel(category: string) {
  return (
    (
      {
        dashboard: "الرئيسية",
        users: "المستخدمون والعقوبات",
        finance: "المالية",
        notifications: "الإشعارات والرسائل الجماعية",
        content: "المحتوى والغرف",
        catalog: "الهدايا والمتجر",
        agency: "الوكالات والمضيفون",
        engagement: "الفعاليات والمهام",
        games: "الألعاب",
        support: "الدعم",
        system: "النظام والمسؤولون",
        general: "عام",
      } as Record<string, string>
    )[category] ?? category
  );
}
