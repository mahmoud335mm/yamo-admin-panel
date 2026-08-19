import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/admins/invites")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="دعوة مسؤول جديد"
        description="الدعوة مرتبطة بالبريد وتنتهي تلقائيًا"
        rpc="admin_create_invite"
        refreshSource="yamo_admin_invites"
        submitLabel="إنشاء الدعوة"
        fields={[
          { key: "email", label: "البريد الإلكتروني", required: true },
          { key: "role", label: "الدور", initial: "admin", required: true },
          {
            key: "days",
            label: "صلاحية الدعوة بالأيام",
            type: "number",
            initial: "7",
            required: true,
          },
        ]}
        buildArgs={(v) => ({ _email: v.email, _role: v.role, _days: Number(v.days) })}
      />
      <YamoDataModule
        title="دعوات المسؤولين"
        description="الدعوات وحالتها وموعد انتهائها"
        source="yamo_admin_invites"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "email", label: "البريد" },
          { key: "role", label: "الدور" },
          { key: "status", label: "الحالة" },
          { key: "expires_at", label: "الانتهاء" },
        ]}
        actions={[
          {
            label: "إلغاء الدعوة",
            rpc: "admin_revoke_invite",
            tone: "destructive",
            buildArgs: (r) => ({ _invite_id: r.id }),
          },
        ]}
      />
    </div>
  ),
});
