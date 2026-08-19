import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, Loader2, ShieldAlert, XCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getYamoAdminMe } from "@/lib/yamo-admin";

type Check = { name: string; pass: boolean; detail: string };
async function runChecks(): Promise<Check[]> {
  const checks: Check[] = [];
  try {
    const me = await getYamoAdminMe();
    checks.push({
      name: "هوية مسؤول Yamo",
      pass: me.roles.length > 0,
      detail: me.roles.join(", "),
    });
  } catch (e) {
    checks.push({ name: "هوية مسؤول Yamo", pass: false, detail: (e as Error).message });
  }
  const wallet = await supabase
    .from("wallets")
    .update({ coins: 0 } as never)
    .eq("user_id", "00000000-0000-0000-0000-000000000000");
  checks.push({
    name: "المحافظ محمية من التعديل المباشر",
    pass: Boolean(wallet.error),
    detail: wallet.error?.message ?? "لم يرفض التعديل",
  });
  const admins = await supabase
    .from("yamo_admin_users" as never)
    .update({ is_active: false } as never)
    .eq("user_id", "00000000-0000-0000-0000-000000000000");
  checks.push({
    name: "حسابات المسؤولين RPC فقط",
    pass: Boolean(admins.error),
    detail: admins.error?.message ?? "لم يرفض التعديل",
  });
  const audit = await supabase
    .from("yamo_admin_audit_logs" as never)
    .delete()
    .eq("id", "00000000-0000-0000-0000-000000000000");
  checks.push({
    name: "سجل العمليات غير قابل للحذف",
    pass: Boolean(audit.error),
    detail: audit.error?.message ?? "لم يرفض الحذف",
  });
  const view = await supabase
    .from("admin_profiles" as never)
    .select("legacy_id")
    .limit(1);
  checks.push({
    name: "واجهات القراءة الإدارية متصلة",
    pass: !view.error,
    detail: view.error?.message ?? "الاتصال ناجح",
  });
  return checks;
}
function SecurityCheck() {
  const q = useQuery({ queryKey: ["yamo-security-check"], queryFn: runChecks });
  return (
    <div className="space-y-5">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-black">
          <ShieldAlert />
          فحص أمان Yamo
        </h1>
        <p className="text-sm text-muted-foreground">
          اختبارات حية على RBAC وRLS الخاصة بقاعدة التطبيق
        </p>
      </div>
      <Card>
        <CardHeader>
          <CardTitle>النتائج</CardTitle>
        </CardHeader>
        <CardContent>
          {q.isLoading ? (
            <div className="grid h-40 place-items-center">
              <Loader2 className="animate-spin" />
            </div>
          ) : (
            <div className="divide-y">
              {q.data?.map((c) => (
                <div className="flex items-center gap-3 py-3" key={c.name}>
                  {c.pass ? (
                    <CheckCircle2 className="text-green-500" />
                  ) : (
                    <XCircle className="text-destructive" />
                  )}
                  <div className="flex-1">
                    <div className="font-medium">{c.name}</div>
                    <div className="text-xs text-muted-foreground">{c.detail}</div>
                  </div>
                  <Badge variant={c.pass ? "default" : "destructive"}>
                    {c.pass ? "ناجح" : "فشل"}
                  </Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
export const Route = createFileRoute("/_authenticated/security-check")({
  component: SecurityCheck,
});
