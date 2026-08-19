import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/families")({
  component: () => (
    <YamoDataModule
      title="العائلات"
      description="العائلات الفعلية وقادتها ومستوياتها ونقاطها وسعتها"
      source="admin_families"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "name", label: "الاسم" },
        { key: "leader_id", label: "القائد" },
        { key: "level", label: "المستوى" },
        { key: "points", label: "النقاط" },
        { key: "member_limit", label: "حد الأعضاء" },
        { key: "created_at", label: "تاريخ الإنشاء" },
      ]}
      actions={[
        {
          label: "حل العائلة",
          rpc: "admin_disband_family",
          tone: "destructive",
          buildArgs: (r) => ({ p_id: r.id, p_reason: "حل من لوحة الإدارة" }),
        },
      ]}
    />
  ),
});
