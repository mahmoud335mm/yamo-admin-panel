import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/posts")({
  component: () => (
    <YamoDataModule
      title="إدارة المنشورات"
      description="مراجعة وإزالة المحتوى مع تسجيل السبب"
      source="admin_posts"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "author_legacy_id", label: "الناشر" },
        { key: "body", label: "المحتوى" },
        { key: "created_at", label: "النشر" },
      ]}
      actions={[
        {
          label: "إزالة",
          rpc: "admin_remove_yamo_post",
          tone: "destructive",
          buildArgs: (r) => ({ p_post_id: r.id, p_reason: "إزالة من لوحة الإدارة" }),
        },
      ]}
    />
  ),
});
