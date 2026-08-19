import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/finance/")({
  component: () => (
    <YamoDataModule
      title="الشحن والسحب"
      description="آخر العمليات المالية المباشرة من Yamo"
      source="admin_wallet_ledger"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "legacy_id", label: "المستخدم" },
        { key: "asset", label: "الأصل" },
        { key: "amount", label: "القيمة" },
        { key: "reason", label: "السبب" },
        { key: "created_at", label: "الوقت" },
      ]}
    />
  ),
});
