import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/gifts")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة أو تعديل هدية"
        description="استخدم نفس كود الهدية لتعديلها"
        rpc="admin_upsert_yamo_gift"
        refreshSource="admin_gifts"
        fields={[
          { key: "id", label: "كود الهدية", required: true },
          { key: "name", label: "الاسم العربي", required: true },
          { key: "price", label: "السعر", type: "number", required: true },
          { key: "category", label: "القسم", initial: "الهدايا" },
          { key: "image", label: "رابط الصورة" },
          { key: "animation", label: "رابط الحركة" },
          { key: "duration", label: "مدة العرض بالثواني", type: "number" },
          { key: "active", label: "ظاهرة بالتطبيق", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_gift_id: v.id,
          p_payload: {
            name_ar: v.name,
            price_coins: Number(v.price),
            category: v.category,
            image_url: v.image,
            animation_url: v.animation,
            duration_seconds: v.duration ? Number(v.duration) : null,
            active: v.active,
          },
        })}
      />
      <YamoDataModule
        title="الهدايا والمتجر"
        description="كتالوج هدايا يامو وأسعاره وحالة الظهور"
        source="admin_gifts"
        columns={[
          { key: "id", label: "الكود" },
          { key: "name_ar", label: "الاسم" },
          { key: "price_coins", label: "السعر" },
          { key: "category", label: "القسم" },
          { key: "active", label: "نشطة" },
        ]}
      />
      <YamoDataModule
        title="سجل إرسال الهدايا"
        description="الحركات الفعلية داخل الغرف وإجمالي الكوينز"
        source="admin_gift_batches"
        columns={[
          { key: "created_at", label: "الوقت" },
          { key: "room_id", label: "الغرفة" },
          { key: "sender_legacy_id", label: "المرسل" },
          { key: "gift_id", label: "الهدية" },
          { key: "quantity", label: "العدد" },
          { key: "receiver_count", label: "المستلمون" },
          { key: "total_coins", label: "إجمالي الكوينز" },
        ]}
      />
    </div>
  ),
});
