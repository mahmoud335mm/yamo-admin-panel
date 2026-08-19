import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";

export const Route = createFileRoute("/_authenticated/distinctive-ids")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة أو تعديل ID مميز"
        description="السعر والصلاحية؛ اترك الأيام فارغة ليكون دائمًا"
        rpc="admin_upsert_distinctive_offer"
        refreshSource="admin_distinctive_id_offers"
        fields={[
          { key: "id", label: "كود العرض", required: true },
          { key: "display", label: "الرقم المميز", required: true },
          { key: "tier", label: "الفئة rare / royal / legendary", initial: "rare" },
          { key: "price", label: "السعر", type: "number", required: true },
          { key: "days", label: "الصلاحية بالأيام", type: "number" },
          { key: "enabled", label: "متاح للشراء", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_id: v.id,
          p_payload: {
            display_value: v.display,
            tier: v.tier,
            price_coins: Number(v.price),
            validity_days: v.days ? Number(v.days) : null,
            enabled: v.enabled,
          },
        })}
      />
      <YamoCommandCard
        title="منح ID من الإدارة"
        description="يمكن منحه لمدة محددة أو دائمًا بدون شراء"
        rpc="admin_grant_distinctive_id"
        fields={[
          { key: "user", label: "ID المستخدم", required: true },
          { key: "offer", label: "كود العرض", required: true },
          { key: "days", label: "الأيام – فارغ يعني دائم", type: "number" },
          { key: "reason", label: "سبب المنح" },
        ]}
        buildArgs={(v) => ({
          p_legacy_id: v.user,
          p_offer_id: v.offer,
          p_days: v.days ? Number(v.days) : null,
          p_reason: v.reason,
        })}
      />
      <YamoDataModule
        title="الـ ID المميز"
        description="الأرقام المميزة المعروضة داخل التطبيق وأسعارها وصلاحيتها"
        source="admin_distinctive_id_offers"
        columns={[
          { key: "display_value", label: "الرقم" },
          { key: "tier", label: "الفئة" },
          { key: "price_coins", label: "السعر" },
          { key: "validity_days", label: "الصلاحية" },
          { key: "enabled", label: "متاح" },
        ]}
      />
      <YamoDataModule
        title="الأرقام المفعلة للمستخدمين"
        description="كل ID مميز مستخدم حاليًا وموعد انتهائه"
        source="admin_distinctive_assignments"
        columns={[
          { key: "legacy_id", label: "ID المستخدم" },
          { key: "display_name", label: "الاسم" },
          { key: "display_value", label: "الرقم المميز" },
          { key: "tier", label: "الفئة" },
          { key: "expires_at", label: "الانتهاء" },
          { key: "equipped", label: "مستخدم" },
        ]}
        actions={[
          {
            label: "إزالة الـ ID",
            rpc: "admin_revoke_distinctive_id",
            tone: "destructive",
            buildArgs: (r) => ({ p_legacy_id: r.legacy_id, p_reason: "إزالة من لوحة الإدارة" }),
          },
        ]}
      />
    </div>
  ),
});
