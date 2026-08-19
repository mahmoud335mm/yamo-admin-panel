import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/operations")({
  component: () => (
    <div className="space-y-5">
      <YamoDataModule
        title="حالة أنظمة يامو"
        description="نتائج مهام حذف الحساب، انتهاء العقوبات، إرسال الإشعارات وفحوصات الخدمة"
        source="admin_system_health"
        columns={[
          { key: "component", label: "الخدمة" },
          { key: "status", label: "الحالة" },
          { key: "message", label: "التفاصيل" },
          { key: "created_at", label: "آخر فحص" },
        ]}
      />
      <YamoDataModule
        title="تسليم إشعارات الهاتف"
        description="حالة كل رسالة FCM وعدد المحاولات والأجهزة المتعطلة"
        source="admin_notification_deliveries"
        columns={[
          { key: "title_ar", label: "الإشعار" },
          { key: "platform", label: "المنصة" },
          { key: "app_version", label: "نسخة التطبيق" },
          { key: "status", label: "التسليم" },
          { key: "attempts", label: "المحاولات" },
          { key: "last_error", label: "آخر خطأ" },
          { key: "created_at", label: "الإنشاء" },
        ]}
      />
    </div>
  ),
});
