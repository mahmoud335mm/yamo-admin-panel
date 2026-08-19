import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/users")({
  component: () => (
    <YamoDataModule
      title="المستخدمون"
      description="حسابات يامو الحقيقية وحالتها ومستواها"
      source="admin_profiles"
      columns={[
        { key: "avatar_url", label: "الصورة", kind: "image" },
        { key: "legacy_id", label: "ID" },
        { key: "display_name", label: "الاسم" },
        { key: "gender", label: "الجنس" },
        { key: "level", label: "LV" },
        { key: "vip_level", label: "VIP" },
        { key: "coins", label: "الكوينز", kind: "number" },
        { key: "pearls", label: "اللؤلؤ", kind: "number" },
        { key: "account_status", label: "الحالة", kind: "status" },
      ]}
      actions={[
        {
          label: "تفعيل",
          rpc: "admin_set_yamo_account_status",
          buildArgs: (r) => ({
            p_legacy_id: r.legacy_id,
            p_status: "active",
            p_note: "تفعيل من لوحة الإدارة",
          }),
        },
        {
          label: "حظر",
          rpc: "admin_set_yamo_account_status",
          tone: "destructive",
          buildArgs: (r) => ({
            p_legacy_id: r.legacy_id,
            p_status: "banned",
            p_note: "حظر من لوحة الإدارة",
          }),
        },
      ]}
    />
  ),
});
