import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/reports")({
  component: () => (
    <YamoDataModule
      title="البلاغات والإشراف"
      description="بلاغات المنشورات المرسلة من التطبيق"
      source="admin_post_reports"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "post_id", label: "المنشور" },
        { key: "reporter_legacy_id", label: "المبلّغ" },
        { key: "reason", label: "السبب" },
        { key: "created_at", label: "الوقت" },
      ]}
      actions={[
        {
          label: "تمت المراجعة",
          rpc: "admin_resolve_yamo_post_report",
          buildArgs: (r) => ({ p_report_id: r.id, p_action: "dismiss" }),
        },
        {
          label: "حذف المحتوى",
          rpc: "admin_resolve_yamo_post_report",
          tone: "destructive",
          buildArgs: (r) => ({ p_report_id: r.id, p_action: "remove_post" }),
        },
      ]}
    />
  ),
});
