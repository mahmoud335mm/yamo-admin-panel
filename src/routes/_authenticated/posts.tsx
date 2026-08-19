import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/posts")({
  component: () => (
    <YamoDataModule
      title="إدارة المنشورات"
      description="مراجعة وإزالة المحتوى مع تسجيل السبب"
      source="admin_posts"
      columns={[
        { key: "media_url", label: "الوسائط", kind: "image" },
        { key: "id", label: "المرجع" },
        { key: "legacy_id", label: "ID الناشر" },
        { key: "display_name", label: "الناشر" },
        { key: "body", label: "المحتوى" },
        { key: "like_count", label: "الإعجابات", kind: "number" },
        { key: "comment_count", label: "التعليقات", kind: "number" },
        { key: "report_count", label: "البلاغات", kind: "number" },
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
