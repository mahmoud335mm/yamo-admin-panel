import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/app-releases")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="نشر نسخة تطبيق"
        description="حدد أقل نسخة مسموحة وفعل التحديث الإجباري عند الحاجة"
        rpc="admin_upsert_app_release"
        refreshSource="admin_app_releases"
        submitLabel="نشر النسخة"
        fields={[
          { key: "platform", label: "المنصة: android / ios", initial: "android", required: true },
          { key: "name", label: "اسم النسخة", required: true },
          { key: "code", label: "Version Code", type: "number", required: true },
          { key: "minimum", label: "أقل Version Code مدعوم", type: "number", required: true },
          { key: "force", label: "تحديث إجباري", type: "checkbox", initial: false },
          { key: "url", label: "رابط التحميل" },
          { key: "notes", label: "ملاحظات التحديث" },
        ]}
        buildArgs={(v) => ({
          p_platform: v.platform,
          p_version_name: v.name,
          p_version_code: Number(v.code),
          p_minimum_code: Number(v.minimum),
          p_force: Boolean(v.force),
          p_url: v.url || null,
          p_notes: v.notes || null,
        })}
      />
      <YamoDataModule
        title="نسخ يامو شات"
        description="سجل الإصدارات وسياسة التحديث التي يقرأها التطبيق"
        source="admin_app_releases"
        columns={[
          { key: "platform", label: "المنصة" },
          { key: "version_name", label: "النسخة" },
          { key: "version_code", label: "الكود" },
          { key: "minimum_supported_code", label: "أقل إصدار" },
          { key: "force_update", label: "إجباري" },
          { key: "active", label: "فعال" },
          { key: "published_at", label: "النشر" },
        ]}
      />
    </div>
  ),
});
