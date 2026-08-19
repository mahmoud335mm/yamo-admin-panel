import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";

export const Route = createFileRoute("/_authenticated/relationships")({
  component: () => (
    <YamoDataModule
      title="علاقات CP والأخوة"
      description="متابعة العلاقات الحقيقية بين المستخدمين وحالتها ونقاطها"
      source="admin_relationships"
      columns={[
        { key: "id", label: "المرجع" },
        { key: "relationship_type", label: "النوع" },
        { key: "requester_id", label: "الطرف الأول" },
        { key: "recipient_id", label: "الطرف الثاني" },
        { key: "status", label: "الحالة" },
        { key: "points", label: "النقاط" },
        { key: "started_at", label: "تاريخ البداية" },
      ]}
      actions={[
        {
          label: "إنهاء إداري",
          rpc: "admin_end_relationship",
          tone: "destructive",
          buildArgs: (r) => ({ p_id: r.id, p_reason: "إنهاء من لوحة الإدارة" }),
        },
      ]}
    />
  ),
});
