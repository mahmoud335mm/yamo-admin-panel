import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/ai")({
  component: () => (
    <YamoDataModule
      title="مركز العمليات الذكي"
      description="مراجعة العمليات والتنبيهات قبل الإجراءات الجماعية"
      source="yamo_admin_audit_logs"
      columns={[
        { key: "created_at", label: "الوقت" },
        { key: "action", label: "الإجراء" },
        { key: "entity_type", label: "النوع" },
        { key: "entity_id", label: "المرجع" },
        { key: "reason", label: "السبب" },
      ]}
    />
  ),
});
