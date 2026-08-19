import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/rooms")({
  component: () => (
    <div className="space-y-5">
      <YamoDataModule
        title="إدارة الغرف"
        description="الغرف الحقيقية، المالك، الحالة والترتيب المميز"
        source="admin_rooms"
        columns={[
          { key: "cover_url", label: "الغلاف", kind: "image" },
          { key: "room_id", label: "ID" },
          { key: "title", label: "الغرفة" },
          { key: "owner_legacy_id", label: "المالك" },
          { key: "category", label: "القسم" },
          { key: "occupancy", label: "المتواجدون", kind: "number" },
          { key: "featured", label: "مميزة", kind: "status" },
          { key: "created_at", label: "الإنشاء" },
        ]}
        actions={[
          {
            label: "إضافة للمميزة",
            rpc: "admin_set_yamo_room_featured",
            buildArgs: (r) => ({ p_room_id: r.room_id, p_featured: true, p_sort_order: 1 }),
          },
          {
            label: "إزالة",
            rpc: "admin_set_yamo_room_featured",
            tone: "destructive",
            buildArgs: (r) => ({ p_room_id: r.room_id, p_featured: false, p_sort_order: 0 }),
          },
          {
            label: "حذف الغرفة",
            rpc: "admin_delete_owned_room",
            tone: "destructive",
            buildArgs: (r) => ({ p_room_id: r.room_id, p_reason: "حذف مخالف من لوحة الإدارة" }),
          },
        ]}
      />
      <YamoDataModule
        title="المتواجدون داخل الغرف"
        description="الحضور الفعلي وآخر نبضة اتصال"
        source="admin_room_presence"
        columns={[
          { key: "room_id", label: "الغرفة" },
          { key: "legacy_id", label: "المستخدم" },
          { key: "display_name", label: "الاسم" },
          { key: "joined_at", label: "الدخول" },
          { key: "last_seen_at", label: "آخر ظهور" },
          { key: "left_at", label: "الخروج" },
        ]}
        actions={[
          {
            label: "إخراج من الغرفة",
            rpc: "admin_remove_room_presence",
            tone: "destructive",
            buildArgs: (r) => ({
              p_room_id: r.room_id,
              p_user_id: r.user_id,
              p_reason: "إخراج من لوحة الإدارة",
            }),
          },
        ]}
      />
    </div>
  ),
});
