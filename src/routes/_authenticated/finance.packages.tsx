import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/finance/packages")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة باقة شحن"
        description="تظهر الباقة مباشرة للمستخدمين"
        rpc="admin_upsert_yamo_recharge_package"
        refreshSource="admin_recharge_packages"
        fields={[
          { key: "title", label: "اسم الباقة", required: true },
          { key: "key", label: "كود الباقة", required: true },
          { key: "country", label: "الدولة", initial: "EG" },
          { key: "coins", label: "الكوينز", type: "number", required: true },
          { key: "bonus", label: "البونص", type: "number", initial: "0" },
          { key: "price", label: "السعر", type: "number", required: true },
          { key: "currency", label: "العملة", initial: "EGP" },
          { key: "enabled", label: "مفعلة", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_id: null,
          p_payload: {
            title: v.title,
            package_key: v.key,
            country_code: v.country,
            coins: Number(v.coins),
            bonus_coins: Number(v.bonus),
            price: Number(v.price),
            currency_code: v.currency,
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="باقات الشحن"
        description="كل الباقات الفعلية في تطبيق يامو"
        source="admin_recharge_packages"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "title", label: "الباقة" },
          { key: "coins", label: "الكوينز" },
          { key: "bonus_coins", label: "البونص" },
          { key: "price", label: "السعر" },
          { key: "currency_code", label: "العملة" },
          { key: "enabled", label: "مفعلة" },
        ]}
      />
    </div>
  ),
});
