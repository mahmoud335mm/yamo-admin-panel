export const CHARGING_AGENCY_STATUS: Record<string, string> = {
  pending: "قيد المراجعة",
  active: "نشطة",
  suspended: "موقوفة",
  under_review: "قيد الفحص",
  closed: "مغلقة",
};

export const CHARGING_TXN_STATUS: Record<string, string> = {
  pending: "قيد التنفيذ",
  completed: "مكتملة",
  reversed: "معكوسة",
  failed: "فشلت",
};

export const AGENT_ROLE_LABELS: Record<string, string> = {
  charging_agency_owner: "مالك وكالة",
  charging_agency_deputy: "نائب مالك",
  charging_agent: "وكيل شحن",
  charging_accountant: "محاسب",
  charging_supervisor: "مشرف",
  charging_region_manager: "مدير منطقة",
  charging_country_manager: "مدير دولة",
};

export const ADJUSTMENT_KIND_LABELS: Record<string, string> = {
  coin_credit: "إضافة كوينز",
  coin_debit: "خصم كوينز",
  pearl_credit: "إضافة لؤلؤ",
  pearl_debit: "خصم لؤلؤ",
};

export function fmtNum(n: number | string | null | undefined): string {
  if (n === null || n === undefined) return "-";
  const v = typeof n === "string" ? Number(n) : n;
  return new Intl.NumberFormat("en-US").format(v);
}

export function fmtDate(d: string | null | undefined): string {
  if (!d) return "-";
  return new Date(d).toLocaleString("ar-EG", { dateStyle: "short", timeStyle: "short" });
}

export function newIdempotencyKey(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}
