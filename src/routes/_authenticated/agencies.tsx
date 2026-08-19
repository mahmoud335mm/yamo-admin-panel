import { createFileRoute } from "@tanstack/react-router";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/agencies")({
  component: () => (
    <div className="space-y-5">
      <YamoDataModule
        title="وكالات يامو"
        description="الوكالات الفعلية وأصحابها وحالتها"
        source="admin_agencies"
        columns={[
          { key: "id", label: "المرجع" },
          { key: "invite_code", label: "كود الدعوة" },
          { key: "name", label: "الاسم" },
          { key: "owner_legacy_id", label: "المالك" },
          { key: "disabled_at", label: "تاريخ التعطيل" },
          { key: "host_count", label: "المضيفون" },
          { key: "created_at", label: "الإنشاء" },
        ]}
        actions={[
          {
            label: "إعادة تفعيل",
            rpc: "admin_set_agency_disabled",
            buildArgs: (r) => ({
              p_agency_id: r.id,
              p_disabled: false,
              p_reason: "تفعيل من الإدارة",
            }),
          },
          {
            label: "تعطيل الوكالة",
            rpc: "admin_set_agency_disabled",
            tone: "destructive",
            buildArgs: (r) => ({
              p_agency_id: r.id,
              p_disabled: true,
              p_reason: "تعطيل من الإدارة",
            }),
          },
        ]}
      />
      <YamoDataModule
        title="تسويات الوكالات"
        description="عمولات الوكالات والفترات المالية"
        source="admin_agency_settlements"
        columns={[
          { key: "agency_name", label: "الوكالة" },
          { key: "period_start", label: "من" },
          { key: "period_end", label: "إلى" },
          { key: "host_pearls", label: "لؤلؤ المضيفين" },
          { key: "commission_pearls", label: "العمولة" },
          { key: "status", label: "الحالة" },
        ]}
        actions={[
          {
            label: "تأكيد التسوية",
            rpc: "admin_set_agency_settlement_status",
            buildArgs: (r) => ({
              p_id: r.id,
              p_status: "settled",
              p_reason: "تمت التسوية من الإدارة",
            }),
          },
          {
            label: "إلغاء التسوية",
            rpc: "admin_set_agency_settlement_status",
            tone: "destructive",
            buildArgs: (r) => ({ p_id: r.id, p_status: "cancelled", p_reason: "إلغاء من الإدارة" }),
          },
        ]}
      />
    </div>
  ),
});
