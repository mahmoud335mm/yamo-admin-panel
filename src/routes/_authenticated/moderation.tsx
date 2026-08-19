import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/moderation")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="تطبيق عقوبة"
        description="حظر كامل أو جزئي، مؤقت أو دائم، مع سبب إلزامي وسجل مراجعة"
        rpc="admin_apply_moderation"
        refreshSource="admin_moderation_actions"
        submitLabel="تطبيق العقوبة"
        fields={[
          { key: "user", label: "ID المستخدم", required: true },
          {
            key: "action",
            label: "suspend / ban / room_ban / message_ban / post_ban / call_ban / warning",
            required: true,
          },
          { key: "days", label: "المدة بالأيام — فارغ للدائم", type: "number" },
          { key: "reason", label: "سبب العقوبة", required: true },
        ]}
        buildArgs={(v) => ({
          p_legacy_id: v.user,
          p_action: v.action,
          p_days: v.days ? Number(v.days) : null,
          p_reason: v.reason,
        })}
      />
      <YamoDataModule
        title="العقوبات والحظر"
        description="كل العقوبات النشطة والمنتهية ومن نفذها"
        source="admin_moderation_actions"
        columns={[
          { key: "legacy_id", label: "المستخدم" },
          { key: "display_name", label: "الاسم" },
          { key: "action_type", label: "العقوبة" },
          { key: "reason", label: "السبب" },
          { key: "expires_at", label: "الانتهاء" },
          { key: "active", label: "نشطة" },
          { key: "created_at", label: "التنفيذ" },
        ]}
        actions={[
          {
            label: "إلغاء العقوبة",
            rpc: "admin_revoke_moderation",
            tone: "destructive",
            buildArgs: (r) => ({ p_id: r.id, p_reason: "إلغاء من لوحة الإدارة" }),
          },
        ]}
      />
    </div>
  ),
});
