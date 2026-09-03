import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/notifications")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إنشاء رسالة فورية"
        description="قسم مستقل للرسائل اليدوية أو الفورية؛ رسائل النظام التلقائية لها قسم منفصل"
        rpc="admin_broadcast_yamo_notification_v2"
        refreshSource="admin_notifications"
        submitLabel="إرسال الآن"
        fields={[
          { key: "title", label: "عنوان الإشعار", required: true },
          { key: "body", label: "النص", required: true },
          { key: "link", label: "الرابط الداخلي" },
          { key: "segment", label: "الفئة: all / vip / hosts", initial: "all", required: true },
          {
            key: "category",
            label: "النوع: event / marketing / system",
            initial: "event",
            required: true,
          },
        ]}
        buildArgs={(v) => ({
          p_title: v.title,
          p_body: v.body,
          p_deep_link: v.link || null,
          p_segment: v.segment,
          p_category: v.category,
        })}
      />
      <YamoDataModule
        title="سجل الرسائل الفورية"
        description="الرسائل اليدوية المسجلة وحالة القراءة"
        source="admin_notifications"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "user_id", label: "المستلم" },
          { key: "title_ar", label: "العنوان" },
          { key: "body_ar", label: "النص" },
          { key: "read_at", label: "القراءة" },
          { key: "created_at", label: "الإرسال" },
        ]}
      />
    </div>
  ),
});
