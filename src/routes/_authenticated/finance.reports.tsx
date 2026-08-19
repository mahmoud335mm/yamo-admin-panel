import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/finance/reports")({
  component: () => (
    <YamoDataModule
      title="تقارير الشحن والسحب"
      description="دفتر أحداث المحفظة غير القابل للتعديل"
      source="admin_wallet_ledger"
      columns={[
        { key: "created_at", label: "الوقت" },
        { key: "legacy_id", label: "المستخدم" },
        { key: "asset", label: "الأصل" },
        { key: "delta", label: "التغيير" },
        { key: "reason", label: "السبب" },
        { key: "reference_id", label: "المرجع" },
      ]}
    />
  ),
});
