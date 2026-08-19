import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/finance/pearl-prices")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة أو تعديل عرض تحويل"
        description="سعر تحويل اللؤلؤ إلى كوينز داخل التطبيق"
        rpc="admin_upsert_yamo_exchange_offer"
        refreshSource="admin_exchange_offers"
        fields={[
          { key: "id", label: "كود العرض", required: true },
          { key: "pearls", label: "عدد اللؤلؤ", type: "number", required: true },
          { key: "coins", label: "عدد الكوينز", type: "number", required: true },
          { key: "enabled", label: "مفعل", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_offer_id: v.id,
          p_payload: {
            pearl_amount: Number(v.pearls),
            coin_amount: Number(v.coins),
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="أسعار اللؤلؤ والتحويل"
        description="العروض الفعلية داخل يامو"
        source="admin_exchange_offers"
        columns={[
          { key: "id", label: "الكود" },
          { key: "pearl_amount", label: "اللؤلؤ" },
          { key: "coin_amount", label: "الكوينز" },
          { key: "enabled", label: "نشط" },
          { key: "sort_order", label: "الترتيب" },
        ]}
      />
    </div>
  ),
});
