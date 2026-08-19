import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/hosts")({
  component: () => (
    <YamoDataModule
      title="المضيفون"
      description="مضيفو يامو المرتبطون بالوكالات"
      source="admin_hosts"
      columns={[
        { key: "legacy_id", label: "المستخدم" },
        { key: "agency_id", label: "الوكالة" },
        { key: "removed_at", label: "تاريخ الإزالة" },
        { key: "total_pearls", label: "إجمالي اللؤلؤ" },
        { key: "joined_at", label: "الانضمام" },
      ]}
      actions={[
        {
          label: "إعادة للوكالة",
          rpc: "admin_set_host_removed",
          buildArgs: (r) => ({
            p_agency_id: r.agency_id,
            p_user_id: r.user_id,
            p_removed: false,
            p_reason: "إعادة من الإدارة",
          }),
        },
        {
          label: "إزالة المضيف",
          rpc: "admin_set_host_removed",
          tone: "destructive",
          buildArgs: (r) => ({
            p_agency_id: r.agency_id,
            p_user_id: r.user_id,
            p_removed: true,
            p_reason: "إزالة من الإدارة",
          }),
        },
      ]}
    />
  ),
});
