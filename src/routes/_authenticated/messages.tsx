import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/messages")({
  component: () => (
    <YamoDataModule
      title="الرسائل والمكالمات"
      description="بيانات التواصل التشغيلية؛ المحتوى الخاص لا يُعرض دون بلاغ"
      source="admin_calls"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "caller_legacy_id", label: "المتصل" },
        { key: "receiver_legacy_id", label: "المستلم" },
        { key: "status", label: "الحالة" },
        { key: "created_at", label: "الوقت" },
      ]}
    />
  ),
});
