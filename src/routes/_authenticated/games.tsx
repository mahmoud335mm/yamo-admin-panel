import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
import { YamoCommandCard } from "@/components/yamo-command-card";
export const Route = createFileRoute("/_authenticated/games")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="تعديل إعدادات لعبة"
        description="تغيير حدود اللعب ونسبة الفوز بدون تحديث التطبيق"
        rpc="admin_update_yamo_game_type"
        refreshSource="admin_games"
        fields={[
          { key: "type", label: "كود اللعبة", required: true },
          { key: "name", label: "الاسم" },
          { key: "min", label: "أقل رهان", type: "number", required: true },
          { key: "max", label: "أعلى رهان", type: "number", required: true },
          { key: "probability", label: "احتمال الفوز 0–1", type: "number", required: true },
          { key: "multiplier", label: "مضاعف الفوز", type: "number", required: true },
          { key: "enabled", label: "مفعلة", type: "checkbox" },
        ]}
        buildArgs={(v) => ({
          p_game_type: v.type,
          p_payload: {
            name_ar: v.name,
            min_bet_coins: Number(v.min),
            max_bet_coins: Number(v.max),
            win_probability: Number(v.probability),
            win_multiplier: Number(v.multiplier),
            enabled: v.enabled,
          },
        })}
      />
      <YamoDataModule
        title="إدارة الألعاب"
        description="أنواع الألعاب، حالة التشغيل ونسب الدفع"
        source="admin_games"
        columns={[
          { key: "game_type", label: "اللعبة" },
          { key: "name_ar", label: "الاسم" },
          { key: "enabled", label: "مفعلة" },
          { key: "min_bet_coins", label: "أقل رهان" },
          { key: "max_bet_coins", label: "أعلى رهان" },
          { key: "win_probability", label: "نسبة الفوز" },
        ]}
      />
    </div>
  ),
});
