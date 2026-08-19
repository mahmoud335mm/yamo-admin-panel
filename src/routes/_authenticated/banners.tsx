import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/banners")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="تحديث بنر التطبيق"
        description="ضع رابط الصورة والعنوان والرابط الداخلي وحالة الظهور"
        rpc="admin_set_yamo_banner"
        refreshSource="app_config"
        fields={[
          { key: "slot", label: "مكان البنر", initial: "home_banner", required: true },
          { key: "image", label: "رابط الصورة 1029×540", required: true },
          { key: "title", label: "العنوان" },
          { key: "link", label: "الرابط الداخلي" },
          { key: "enabled", label: "ظاهر", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_key: v.slot,
          p_value: { image_url: v.image, title: v.title, deep_link: v.link, enabled: v.enabled },
        })}
      />
      <YamoDataModule
        title="البنرات والمحتوى الرئيسي"
        description="الإعدادات التي يقرأها التطبيق مباشرة"
        source="app_config"
        columns={[
          { key: "config_key", label: "المفتاح" },
          { key: "config_value", label: "القيمة" },
          { key: "updated_at", label: "آخر تحديث" },
        ]}
      />
    </div>
  ),
});
