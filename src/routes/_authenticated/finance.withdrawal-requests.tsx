import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/finance/withdrawal-requests")({
  component: () => (
    <YamoDataModule
      title="طلبات السحب"
      description="طلبات سحب يامو المباشرة"
      source="admin_withdrawal_requests"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "legacy_id", label: "المستخدم" },
        { key: "display_name", label: "الاسم" },
        { key: "pearls", label: "اللؤلؤ" },
        { key: "reserved_pearls", label: "المحجوز" },
        { key: "payout_amount", label: "قيمة التحويل" },
        { key: "currency_code", label: "العملة" },
        { key: "method_name", label: "الوسيلة" },
        { key: "payout_details", label: "بيانات الاستلام" },
        { key: "status", label: "الحالة" },
        { key: "created_at", label: "الطلب" },
      ]}
      actions={[
        {
          label: "بدء المراجعة",
          rpc: "admin_review_withdrawal",
          buildArgs: (r) => ({
            p_request_id: r.id,
            p_action: "review",
            p_note: "قيد مراجعة الإدارة",
          }),
        },
        {
          label: "تم التحويل",
          rpc: "admin_review_withdrawal",
          buildArgs: (r) => ({
            p_request_id: r.id,
            p_action: "complete",
            p_note: "اعتماد من لوحة الإدارة",
          }),
          prompts: [
            {
              key: "p_payout_reference",
              message: "اكتب رقم مرجع التحويل للمستخدم",
              required: true,
            },
            { key: "p_payout_proof_path", message: "مسار/رابط إثبات التحويل (اختياري)" },
          ],
        },
        {
          label: "رفض ورد اللؤلؤ",
          rpc: "admin_review_withdrawal",
          tone: "destructive",
          buildArgs: (r) => ({
            p_request_id: r.id,
            p_action: "reject",
            p_note: "رفض من لوحة الإدارة",
          }),
          prompts: [{ key: "p_note", message: "اكتب سبب الرفض", required: true }],
        },
      ]}
    />
  ),
});
