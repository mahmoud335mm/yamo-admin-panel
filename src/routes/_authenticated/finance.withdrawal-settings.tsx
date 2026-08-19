import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/finance/withdrawal-settings")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة باقة سحب"
        description="قيمة اللؤلؤ والرسوم والمبلغ الذي يستلمه المستخدم"
        rpc="admin_upsert_yamo_withdraw_package"
        refreshSource="admin_withdraw_packages"
        fields={[
          { key: "title", label: "اسم الباقة", required: true },
          { key: "key", label: "كود الباقة", required: true },
          { key: "country", label: "الدولة", initial: "EG" },
          { key: "pearls", label: "اللؤلؤ", type: "number", required: true },
          { key: "fee", label: "رسوم اللؤلؤ", type: "number", initial: "0" },
          { key: "amount", label: "مبلغ التحويل", type: "number", required: true },
          { key: "currency", label: "العملة", initial: "EGP" },
          { key: "enabled", label: "مفعلة", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_id: null,
          p_payload: {
            title: v.title,
            package_key: v.key,
            country_code: v.country,
            pearls: Number(v.pearls),
            fee_pearls: Number(v.fee),
            payout_amount: Number(v.amount),
            currency_code: v.currency,
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="إعدادات السحب"
        description="الباقات الفعلية في يامو"
        source="admin_withdraw_packages"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "title", label: "الباقة" },
          { key: "pearls", label: "اللؤلؤ" },
          { key: "fee_pearls", label: "الرسوم" },
          { key: "payout_amount", label: "القيمة" },
          { key: "currency_code", label: "العملة" },
          { key: "enabled", label: "مفعلة" },
        ]}
      />
    </div>
  ),
});
