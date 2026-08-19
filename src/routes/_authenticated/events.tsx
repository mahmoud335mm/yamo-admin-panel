import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/events")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إنشاء فعالية"
        description="تظهر داخل تطبيق يامو في الفترة المحددة"
        rpc="upsert_yamo_event"
        refreshSource="admin_events"
        fields={[
          { key: "slug", label: "كود الفعالية", required: true },
          { key: "title", label: "العنوان", required: true },
          { key: "description", label: "الوصف" },
          { key: "banner", label: "رابط البنر" },
          { key: "start", label: "البداية", type: "datetime-local", required: true },
          { key: "end", label: "النهاية", type: "datetime-local", required: true },
          { key: "metric", label: "مقياس الترتيب", initial: "ROOM_GIFT_COINS" },
        ]}
        buildArgs={(v) => ({
          p_event_id: null,
          p_payload: {
            slug: v.slug,
            title_ar: v.title,
            description_ar: v.description,
            banner_url: v.banner,
            starts_at: new Date(String(v.start)).toISOString(),
            ends_at: new Date(String(v.end)).toISOString(),
            status: "draft",
            leaderboard_metric: v.metric,
          },
        })}
      />
      <YamoDataModule
        title="الفعاليات"
        description="فعاليات يامو وفترات التشغيل وحالة النشر"
        source="admin_events"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "title_ar", label: "العنوان" },
          { key: "status", label: "الحالة" },
          { key: "starts_at", label: "البداية" },
          { key: "ends_at", label: "النهاية" },
        ]}
        actions={[
          {
            label: "نشر",
            rpc: "set_yamo_event_status",
            buildArgs: (r) => ({ p_event_id: r.id, p_status: "live" }),
          },
          {
            label: "إيقاف",
            rpc: "set_yamo_event_status",
            tone: "destructive",
            buildArgs: (r) => ({ p_event_id: r.id, p_status: "ended" }),
          },
        ]}
      />
    </div>
  ),
});
