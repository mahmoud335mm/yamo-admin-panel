import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";

export const Route = createFileRoute("/_authenticated/inventory")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة أو تعديل مقتنى"
        description="إطار أو دخلة أو فقاعة شات"
        rpc="admin_upsert_yamo_store_asset"
        refreshSource="admin_store_assets"
        fields={[
          { key: "kind", label: "النوع: frame / entry_effect / chat_bubble", required: true },
          { key: "key", label: "كود المقتنى", required: true },
          { key: "name", label: "الاسم", required: true },
          { key: "price", label: "السعر", type: "number", required: true },
          { key: "days", label: "مدة الصلاحية بالأيام", type: "number" },
          { key: "preview", label: "رابط المعاينة" },
          { key: "enabled", label: "متاح", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_asset_kind: v.kind,
          p_asset_key: v.key,
          p_payload: {
            name_ar: v.name,
            price_coins: Number(v.price),
            duration_days: v.days ? Number(v.days) : null,
            preview_url: v.preview,
            enabled: v.enabled,
          },
        })}
      />
      <YamoCommandCard
        title="منح مقتنى لمستخدم"
        description="يمكن منحه مؤقتًا أو دائمًا بدون شراء"
        rpc="admin_grant_user_asset"
        refreshSource="admin_user_assets"
        fields={[
          { key: "user", label: "ID المستخدم", required: true },
          { key: "kind", label: "نوع المقتنى", required: true },
          { key: "asset", label: "كود المقتنى", required: true },
          { key: "days", label: "الأيام – فارغ يعني دائم", type: "number" },
          { key: "reason", label: "سبب المنح" },
        ]}
        buildArgs={(v) => ({
          p_legacy_id: v.user,
          p_asset_kind: v.kind,
          p_asset_key: v.asset,
          p_days: v.days ? Number(v.days) : null,
          p_reason: v.reason,
        })}
      />
      <YamoDataModule
        title="المقتنيات"
        description="إطارات الدخول والفقاعات وباقي مقتنيات متجر يامو"
        source="admin_store_assets"
        columns={[
          { key: "asset_kind", label: "النوع" },
          { key: "asset_key", label: "الكود" },
          { key: "name_ar", label: "الاسم" },
          { key: "price_coins", label: "السعر" },
          { key: "duration_days", label: "المدة" },
          { key: "enabled", label: "متاح" },
        ]}
      />
      <YamoDataModule
        title="مقتنيات المستخدمين"
        description="المقتنيات الممنوحة أو المشتراة وموعد انتهائها"
        source="admin_user_assets"
        columns={[
          { key: "legacy_id", label: "المستخدم" },
          { key: "display_name", label: "الاسم" },
          { key: "asset_kind", label: "النوع" },
          { key: "asset_key", label: "المقتنى" },
          { key: "granted_at", label: "المنح" },
          { key: "expires_at", label: "الانتهاء" },
        ]}
        actions={[
          {
            label: "سحب المقتنى",
            rpc: "admin_revoke_user_asset",
            tone: "destructive",
            buildArgs: (r) => ({
              p_user_id: r.user_id,
              p_asset_kind: r.asset_kind,
              p_asset_key: r.asset_key,
              p_reason: "سحب من لوحة الإدارة",
            }),
          },
        ]}
      />
    </div>
  ),
});
