import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/daily-login")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة أو تعديل مهمة"
        description="المهمة تظهر مباشرة في مركز المهام"
        rpc="admin_upsert_yamo_task"
        refreshSource="admin_tasks"
        fields={[
          { key: "id", label: "كود المهمة", required: true },
          { key: "title", label: "العنوان", required: true },
          { key: "subtitle", label: "الوصف" },
          { key: "section", label: "القسم normal / agency / agent", initial: "normal" },
          { key: "metric", label: "نوع القياس", initial: "MESSAGE_REPLIES", required: true },
          { key: "reset", label: "زمن التجديد بالثواني", type: "number" },
          { key: "enabled", label: "مفعلة", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_task_id: v.id,
          p_payload: {
            title_ar: v.title,
            subtitle_ar: v.subtitle,
            section: v.section,
            metric: v.metric,
            reset_every_seconds: v.reset ? Number(v.reset) : null,
            enabled: v.enabled,
          },
        })}
      />
      <YamoCommandCard
        title="إضافة مرحلة ومكافأة"
        description="اربط المكافأة بكود المهمة وحدد شرط الاستحقاق"
        rpc="admin_upsert_yamo_task_milestone"
        refreshSource="admin_task_milestones"
        fields={[
          { key: "id", label: "كود المرحلة", required: true },
          { key: "task", label: "كود المهمة", required: true },
          { key: "target", label: "القيمة المطلوبة", type: "number", required: true },
          {
            key: "asset",
            label: "COINS / PEARLS / PROFILE_FRAME / ENTRANCE_EFFECT",
            initial: "COINS",
          },
          { key: "value", label: "قيمة المكافأة", type: "number", required: true },
          { key: "assetKey", label: "كود الإطار أو الدخلة" },
          { key: "title", label: "اسم المكافأة" },
        ]}
        buildArgs={(v) => ({
          p_milestone_id: v.id,
          p_payload: {
            task_id: v.task,
            target_value: Number(v.target),
            reward_asset: v.asset,
            reward_value: Number(v.value),
            reward_asset_key: v.assetKey || null,
            reward_title_ar: v.title,
          },
        })}
      />
      <YamoDataModule
        title="المهام والمكافآت اليومية"
        description="المهام والمكافآت التي تظهر داخل يامو"
        source="admin_tasks"
        columns={[
          { key: "id", label: "الكود" },
          { key: "title_ar", label: "المهمة" },
          { key: "metric", label: "نوع القياس" },
          { key: "reset_every_seconds", label: "التجديد" },
          { key: "enabled", label: "نشطة" },
        ]}
      />
      <YamoDataModule
        title="مراحل ومكافآت المهام"
        description="كل شروط الإنجاز والمكافآت المرتبطة بها"
        source="admin_task_milestones"
        columns={[
          { key: "id", label: "المرحلة" },
          { key: "task_id", label: "المهمة" },
          { key: "target_value", label: "الشرط" },
          { key: "reward_asset", label: "نوع المكافأة" },
          { key: "reward_value", label: "القيمة" },
          { key: "reward_asset_key", label: "المقتنى" },
        ]}
      />
    </div>
  ),
});
