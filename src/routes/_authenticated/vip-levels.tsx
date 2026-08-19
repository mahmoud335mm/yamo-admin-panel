import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";

export const Route = createFileRoute("/_authenticated/vip-levels")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="منح VIP لمستخدم"
        description="تفعيل VIP من الإدارة لمدة محددة"
        rpc="admin_grant_yamo_vip"
        refreshSource="admin_vip_tiers"
        fields={[
          { key: "legacy", label: "ID المستخدم", required: true },
          { key: "level", label: "المستوى 1–4", type: "number", required: true },
          { key: "days", label: "المدة بالأيام", type: "number", required: true },
          { key: "reason", label: "سبب المنح" },
        ]}
        buildArgs={(v) => ({
          p_legacy_id: v.legacy,
          p_level: Number(v.level),
          p_days: Number(v.days),
          p_reason: v.reason,
        })}
      />
      <YamoCommandCard
        title="إنشاء أو تعديل مستوى VIP"
        description="الأسعار والمدة والمزايا التي يقرأها التطبيق"
        rpc="admin_upsert_yamo_vip_tier"
        refreshSource="admin_vip_tiers"
        fields={[
          { key: "level", label: "المستوى", type: "number", required: true },
          { key: "name", label: "الاسم", required: true },
          { key: "price", label: "السعر بالكوينز", type: "number", required: true },
          { key: "days", label: "المدة", type: "number", required: true },
          { key: "frame", label: "كود الإطار" },
          { key: "entry", label: "كود الدخلة" },
          { key: "enabled", label: "مفعل", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_level: Number(v.level),
          p_payload: {
            name_ar: v.name,
            price_coins: Number(v.price),
            duration_days: Number(v.days),
            frame_key: v.frame,
            entry_effect_key: v.entry,
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="VIP والمستويات"
        description="باقات VIP الفعلية ومددها وأسعارها والمزايا المرتبطة بها"
        source="admin_vip_tiers"
        columns={[
          { key: "level", label: "المستوى" },
          { key: "name_ar", label: "الاسم" },
          { key: "price_coins", label: "السعر" },
          { key: "duration_days", label: "المدة بالأيام" },
          { key: "frame_key", label: "الإطار" },
          { key: "enabled", label: "مفعل" },
        ]}
      />
      <YamoDataModule
        title="اشتراكات VIP النشطة والمنتهية"
        description="المستخدمون الذين تم شراء أو منح VIP لهم"
        source="admin_vip_subscriptions"
        columns={[
          { key: "legacy_id", label: "ID المستخدم" },
          { key: "display_name", label: "الاسم" },
          { key: "level", label: "المستوى" },
          { key: "expires_at", label: "الانتهاء" },
          { key: "auto_renew", label: "تجديد تلقائي" },
        ]}
        actions={[
          {
            label: "إلغاء VIP",
            rpc: "admin_revoke_yamo_vip",
            tone: "destructive",
            buildArgs: (r) => ({ p_legacy_id: r.legacy_id, p_reason: "إلغاء من لوحة الإدارة" }),
          },
        ]}
      />
    </div>
  ),
});
