import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/economy")({
  component: () => (
    <YamoDataModule
      title="المحافظ والاقتصاد"
      description="أرصدة الكوينز واللؤلؤ الحقيقية"
      source="admin_wallets"
      columns={[
        { key: "legacy_id", label: "المستخدم" },
        { key: "coins", label: "كوينز" },
        { key: "pearls", label: "لؤلؤ" },
        { key: "updated_at", label: "آخر تحديث" },
      ]}
    />
  ),
});
