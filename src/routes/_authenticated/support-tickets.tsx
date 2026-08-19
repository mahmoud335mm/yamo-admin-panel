import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/support-tickets")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="الرد على تذكرة"
        description="غيّر الحالة وسجّل الرد الذي سيظهر للمستخدم"
        rpc="admin_update_support_ticket"
        refreshSource="admin_support_tickets"
        submitLabel="حفظ الرد"
        fields={[
          { key: "id", label: "رقم التذكرة", required: true },
          {
            key: "status",
            label: "الحالة: open / in_progress / resolved / closed",
            initial: "resolved",
            required: true,
          },
          { key: "reply", label: "رد الإدارة", required: true },
        ]}
        buildArgs={(v) => ({ p_id: v.id, p_status: v.status, p_reply: v.reply })}
      />
      <YamoDataModule
        title="تذاكر الدعم"
        description="صندوق الدعم الحقيقي مرتب حسب الأولوية والحالة"
        source="admin_support_tickets"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "legacy_id", label: "المستخدم" },
          { key: "category", label: "القسم" },
          { key: "subject", label: "الموضوع" },
          { key: "priority", label: "الأولوية" },
          { key: "status", label: "الحالة" },
          { key: "created_at", label: "الإنشاء" },
        ]}
        actions={[
          {
            label: "قيد المعالجة",
            rpc: "admin_update_support_ticket",
            buildArgs: (r) => ({ p_id: r.id, p_status: "in_progress", p_reply: null }),
          },
          {
            label: "إغلاق",
            rpc: "admin_update_support_ticket",
            tone: "destructive",
            buildArgs: (r) => ({
              p_id: r.id,
              p_status: "closed",
              p_reply: "تم إغلاق التذكرة بواسطة الدعم",
            }),
          },
        ]}
      />
    </div>
  ),
});
