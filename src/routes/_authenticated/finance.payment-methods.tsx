import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/finance/payment-methods")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة وسيلة دفع"
        description="وسيلة شحن أو سحب أو الاثنين"
        rpc="admin_upsert_yamo_payment_method"
        refreshSource="admin_payment_methods"
        fields={[
          { key: "name", label: "الاسم", required: true },
          { key: "key", label: "الكود", required: true },
          { key: "flow", label: "recharge / withdrawal / both", initial: "recharge" },
          { key: "country", label: "الدولة", initial: "EG" },
          { key: "instructions", label: "التعليمات" },
          { key: "receiver", label: "رقم أو حساب الاستلام" },
          { key: "enabled", label: "مفعلة", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_id: null,
          p_payload: {
            display_name: v.name,
            method_key: v.key,
            flow: v.flow,
            country_code: v.country,
            instructions: v.instructions,
            receiver_value: v.receiver,
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="وسائل الدفع"
        description="وسائل الدفع الحقيقية التي تظهر داخل يامو"
        source="admin_payment_methods"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "display_name", label: "الاسم" },
          { key: "flow", label: "النوع" },
          { key: "country_code", label: "الدولة" },
          { key: "receiver_value", label: "بيانات الاستلام" },
          { key: "enabled", label: "مفعلة" },
        ]}
      />
    </div>
  ),
});
