import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/audit")({
  component: () => (
    <YamoDataModule
      title="سجل العمليات"
      description="سجل غير قابل للتعديل لكل إجراءات المسؤولين"
      source="admin_audit_logs"
      columns={[
        { key: "created_at", label: "الوقت" },
        { key: "actor_email", label: "المسؤول" },
        { key: "action", label: "الإجراء" },
        { key: "entity_type", label: "القسم" },
        { key: "entity_id", label: "المرجع" },
        { key: "reason", label: "السبب" },
      ]}
    />
  ),
});
