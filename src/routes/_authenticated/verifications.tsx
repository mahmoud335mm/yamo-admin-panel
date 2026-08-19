import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/verifications")({
  component: () => (
    <YamoDataModule
      title="التحقق من الهوية"
      description="مراجعة طلبات الشخص الحقيقي ومطابقة البيانات قبل منح التوثيق"
      source="admin_verification_requests"
      columns={[
        { key: "legacy_id", label: "ID المستخدم" },
        { key: "display_name", label: "الاسم" },
        { key: "request_type", label: "نوع التحقق" },
        { key: "requested_gender", label: "الجنس المطلوب" },
        { key: "status", label: "الحالة" },
        { key: "created_at", label: "وقت الطلب" },
      ]}
      actions={[
        {
          label: "قبول",
          rpc: "admin_review_verification",
          buildArgs: (r) => ({
            p_id: r.id,
            p_action: "approved",
            p_note: "تمت المطابقة من لوحة الإدارة",
          }),
        },
        {
          label: "رفض",
          rpc: "admin_review_verification",
          tone: "destructive",
          buildArgs: (r) => ({ p_id: r.id, p_action: "rejected", p_note: "لم تجتز المطابقة" }),
        },
      ]}
    />
  ),
});
