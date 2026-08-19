import { createFileRoute } from "@tanstack/react-router";
import { YamoCommandCard } from "@/components/yamo-command-card";
import { YamoDataModule } from "@/components/yamo-data-module";
export const Route = createFileRoute("/_authenticated/wallet-adjustments")({
  component: () => (
    <div className="space-y-5">
      <YamoCommandCard
        title="إضافة أو خصم رصيد"
        description="اكتب قيمة موجبة للإضافة وسالبة للخصم؛ يمنع الرصيد السالب والتكرار تلقائيًا"
        rpc="admin_adjust_yamo_wallet"
        refreshSource="admin_wallet_ledger"
        submitLabel="تنفيذ تعديل الرصيد"
        fields={[
          { key: "user", label: "ID المستخدم", required: true },
          { key: "asset", label: "coins أو pearls", initial: "coins", required: true },
          { key: "amount", label: "القيمة (+/-)", type: "number", required: true },
          { key: "reason", label: "سبب واضح", required: true },
        ]}
        buildArgs={(v) => ({
          p_legacy_id: v.user,
          p_asset: v.asset,
          p_amount: Number(v.amount),
          p_reason: v.reason,
          p_idempotency_key: crypto.randomUUID(),
        })}
      />
      <YamoDataModule
        title="سجل تعديلات الأرصدة"
        description="كل حركة مالية مسجلة وغير قابلة للحذف"
        source="admin_wallet_ledger"
        columns={[
          { key: "created_at", label: "الوقت" },
          { key: "legacy_id", label: "المستخدم" },
          { key: "asset", label: "الأصل" },
          { key: "amount", label: "القيمة" },
          { key: "reason", label: "النوع" },
          { key: "reference_id", label: "المرجع" },
        ]}
      />
    </div>
  ),
});
