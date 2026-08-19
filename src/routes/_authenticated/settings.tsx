import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/settings")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="عملة مؤشرات الربح"
        description="العملة التي تجمع بها الرئيسية الدخل والمصروفات بدون خلط العملات"
        rpc="admin_set_yamo_app_config"
        refreshSource="app_config"
        fields={[
          { key: "currency", label: "كود العملة مثل EGP أو USD", initial: "EGP", required: true },
        ]}
        buildArgs={(v) => ({
          p_key: "dashboard_currency",
          p_value: { currency: String(v.currency).toUpperCase() },
        })}
      />
      <YamoCommandCard
        title="تعديل إعداد مباشر"
        description="القيمة بصيغة JSON وتصل للتطبيق بدون إصدار APK جديد"
        rpc="admin_set_yamo_app_config"
        refreshSource="app_config"
        fields={[
          { key: "key", label: "مفتاح الإعداد", required: true },
          { key: "value", label: 'القيمة JSON مثال: {"enabled":true}', required: true },
        ]}
        buildArgs={(v) => ({ p_key: v.key, p_value: JSON.parse(String(v.value)) })}
      />
      <YamoCommandCard
        title="إدارة قاعدة احتساب المستوى"
        description="النقاط تضاف تلقائيًا عند تحقق النشاط داخل التطبيق"
        rpc="admin_upsert_level_rule"
        refreshSource="admin_level_rules"
        fields={[
          { key: "key", label: "كود القاعدة", required: true },
          { key: "title", label: "اسم النشاط", required: true },
          { key: "icon", label: "كود الأيقونة", initial: "star" },
          { key: "coins", label: "كل عدد كوينز", type: "number", initial: "1", required: true },
          { key: "points", label: "النقاط المضافة", type: "number", required: true },
          { key: "enabled", label: "مفعلة", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_rule_key: v.key,
          p_payload: {
            title_ar: v.title,
            icon_key: v.icon,
            coins_required: Number(v.coins),
            points_granted: Number(v.points),
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="إعدادات التطبيق"
        description="Remote Config الحقيقي الذي يقرأه يامو"
        source="app_config"
        columns={[
          { key: "config_key", label: "الإعداد" },
          { key: "config_value", label: "القيمة" },
          { key: "updated_at", label: "آخر تعديل" },
        ]}
      />
      <YamoDataModule
        title="قواعد المستويات"
        description="المصادر الحقيقية التي ترفع مستوى المستخدم تلقائيًا"
        source="admin_level_rules"
        columns={[
          { key: "rule_key", label: "الكود" },
          { key: "title_ar", label: "النشاط" },
          { key: "coins_required", label: "الكوينز المطلوبة" },
          { key: "points_granted", label: "النقاط" },
          { key: "enabled", label: "مفعلة" },
          { key: "updated_at", label: "آخر تعديل" },
        ]}
      />
    </div>
  ),
});
