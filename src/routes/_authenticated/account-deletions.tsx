import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/account-deletions")({
  component: () => (
    <YamoDataModule
      title="طلبات حذف الحساب"
      description="مهلة 7 أيام ومراجعة الشروط قبل الحذف النهائي"
      source="admin_account_deletion_requests"
      columns={[
        { key: "legacy_id", label: "المستخدم" },
        { key: "display_name", label: "الاسم" },
        { key: "coins", label: "كوينز" },
        { key: "pearls", label: "لؤلؤ" },
        { key: "reason", label: "السبب" },
        { key: "status", label: "الحالة" },
        { key: "eligible_at", label: "موعد الاستحقاق" },
      ]}
      actions={[
        {
          label: "موافقة",
          rpc: "admin_review_account_deletion",
          buildArgs: (r) => ({ p_id: r.id, p_action: "approve", p_note: "موافقة من لوحة الإدارة" }),
        },
        {
          label: "رفض",
          rpc: "admin_review_account_deletion",
          tone: "destructive",
          buildArgs: (r) => ({ p_id: r.id, p_action: "reject", p_note: "رفض من لوحة الإدارة" }),
        },
      ]}
    />
  ),
});
