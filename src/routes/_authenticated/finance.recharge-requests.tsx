import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/finance/recharge-requests")({
  component: () => (
    <YamoDataModule
      title="طلبات الشحن"
      description="مراجعة إثباتات الدفع واعتماد الكوينز مرة واحدة فقط"
      source="admin_recharge_requests"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "legacy_id", label: "المستخدم" },
        { key: "sender_name", label: "اسم المحوّل" },
        { key: "sender_account", label: "رقم المحوّل" },
        { key: "coins", label: "الكوينز" },
        { key: "paid_amount", label: "المبلغ" },
        { key: "currency_code", label: "العملة" },
        { key: "status", label: "الحالة" },
        { key: "proof_path", label: "الإثبات" },
        { key: "transaction_reference", label: "رقم التحويل" },
        { key: "created_at", label: "الطلب" },
      ]}
      actions={[
        {
          label: "بدء المراجعة",
          rpc: "admin_review_recharge",
          buildArgs: (r) => ({
            p_request_id: r.id,
            p_action: "review",
            p_note: "قيد مراجعة الإدارة",
          }),
        },
        {
          label: "اعتماد وشحن",
          rpc: "admin_review_recharge",
          buildArgs: (r) => ({
            p_request_id: r.id,
            p_action: "complete",
            p_note: "اعتماد من لوحة الإدارة",
          }),
          prompts: [{ key: "p_transaction_reference", message: "رقم عملية التحويل (اختياري)" }],
        },
        {
          label: "طلب إثبات جديد",
          rpc: "admin_review_recharge",
          buildArgs: (r) => ({ p_request_id: r.id, p_action: "request_proof" }),
          prompts: [{ key: "p_note", message: "اكتب سبب طلب إثبات جديد", required: true }],
        },
        {
          label: "رفض",
          rpc: "admin_review_recharge",
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
