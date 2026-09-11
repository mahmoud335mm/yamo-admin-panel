import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import worldCountries from "world-countries";
import { ArrowRight, Loader2, Plus } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { PermissionGuard } from "@/components/permission-guard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { fmtNum } from "@/lib/charging-utils";

export const Route = createFileRoute("/_authenticated/charging-pricing")({
  component: () => (
    <PermissionGuard permission="charging_pricing.read">
      <ChargingPricingPanel />
    </PermissionGuard>
  ),
});
type PackageType = "coin" | "pearl_buy" | "pearl_exchange" | "usdt";
type PackageRow = {
  id: string;
  package_type: PackageType;
  name: string;
  country_code: string | null;
  currency: string;
  money_amount: number;
  coin_amount: number;
  pearl_amount: number;
  usdt_amount: number;
  bonus_amount: number;
  fee_percentage: number;
  discount_percentage: number;
  agent_only: boolean;
  enabled: boolean;
};
const TYPES: Record<PackageType, string> = {
  coin: "باقات شحن الكوينز",
  pearl_buy: "شراء وسحب اللؤلؤ",
  pearl_exchange: "تبديل اللؤلؤ إلى كوينز",
  usdt: "باقات USDT للوكلاء",
};
const COUNTRIES = worldCountries
  .filter((c) => c.status === "officially-assigned")
  .map((c) => ({
    code: c.cca2,
    name: c.translations.ara?.common ?? c.name.common,
    flag: c.flag,
    currency: Object.keys(c.currencies ?? {})[0] ?? "USD",
  }))
  .sort((a, b) => a.name.localeCompare(b.name, "ar"));

export function ChargingPricingPanel() {
  const packs = useQuery({
    queryKey: ["charging_packages"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("charging_packages")
        .select("*")
        .order("sort_order")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as PackageRow[];
    },
  });
  const toggle = useMutation({
    mutationFn: async (v: { id: string; enabled: boolean }) => {
      const { error } = await supabase.rpc("admin_toggle_charging_package", {
        _id: v.id,
        _enabled: v.enabled,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      packs.refetch();
      toast.success("تم تحديث حالة الباقة");
    },
    onError: (e: Error) => toast.error(e.message),
  });
  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black">الأسعار والباقات</h1>
          <p className="text-sm text-muted-foreground">
            تحكم في الكوينز واللؤلؤ والتبديل وUSDT حسب الدولة.
          </p>
        </div>
        <div className="flex gap-2">
          <Link to="/charging-agencies">
            <Button variant="outline">
              <ArrowRight className="ml-2 h-4 w-4" />
              وكالة الشحن
            </Button>
          </Link>
          <PackageDialog done={() => packs.refetch()} />
        </div>
      </div>
      <Tabs defaultValue="coin">
        <TabsList className="h-auto flex-wrap">
          {(Object.keys(TYPES) as PackageType[]).map((t) => (
            <TabsTrigger key={t} value={t}>
              {TYPES[t]}
            </TabsTrigger>
          ))}
        </TabsList>
        {(Object.keys(TYPES) as PackageType[]).map((t) => (
          <TabsContent key={t} value={t}>
            <PackageTable
              rows={(packs.data ?? []).filter((p) => p.package_type === t)}
              loading={packs.isLoading}
              toggle={(id, enabled) => toggle.mutate({ id, enabled })}
            />
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
function PackageTable({
  rows,
  loading,
  toggle,
}: {
  rows: PackageRow[];
  loading: boolean;
  toggle: (id: string, enabled: boolean) => void;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">الباقات الحالية</CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <Loader2 className="mx-auto animate-spin" />
        ) : !rows.length ? (
          <div className="py-12 text-center text-muted-foreground">
            لا توجد باقات — اضغط إضافة باقة
          </div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الباقة</TableHead>
                  <TableHead>الدولة</TableHead>
                  <TableHead>المبلغ</TableHead>
                  <TableHead>كوينز</TableHead>
                  <TableHead>لؤلؤ</TableHead>
                  <TableHead>USDT</TableHead>
                  <TableHead>خصم</TableHead>
                  <TableHead>الظهور</TableHead>
                  <TableHead>الحالة</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell>
                      <b>{p.name}</b>
                      {p.bonus_amount > 0 && (
                        <div className="text-xs text-emerald-500">
                          +{fmtNum(p.bonus_amount)} مكافأة
                        </div>
                      )}
                    </TableCell>
                    <TableCell dir="ltr">{p.country_code ?? "GLOBAL"}</TableCell>
                    <TableCell dir="ltr">
                      {fmtNum(p.money_amount)} {p.currency}
                    </TableCell>
                    <TableCell dir="ltr">{fmtNum(p.coin_amount)}</TableCell>
                    <TableCell dir="ltr">{fmtNum(p.pearl_amount)}</TableCell>
                    <TableCell dir="ltr">{fmtNum(p.usdt_amount)}</TableCell>
                    <TableCell dir="ltr">{fmtNum(p.discount_percentage)}%</TableCell>
                    <TableCell>
                      {p.agent_only ? (
                        <Badge>وكلاء فقط</Badge>
                      ) : (
                        <Badge variant="secondary">الجميع</Badge>
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Switch checked={p.enabled} onCheckedChange={(v) => toggle(p.id, v)} />
                        <span>{p.enabled ? "تعمل" : "متوقفة"}</span>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function PackageDialog({ done }: { done: () => void }) {
  const [open, setOpen] = useState(false),
    [type, setType] = useState<PackageType>("coin"),
    [name, setName] = useState(""),
    [country, setCountry] = useState("GLOBAL"),
    [currency, setCurrency] = useState("USD"),
    [money, setMoney] = useState("0"),
    [coins, setCoins] = useState("0"),
    [pearls, setPearls] = useState("0"),
    [usdt, setUsdt] = useState("0"),
    [bonus, setBonus] = useState("0"),
    [fee, setFee] = useState("0"),
    [discount, setDiscount] = useState("0"),
    [agentOnly, setAgentOnly] = useState(false);
  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("admin_save_charging_package", {
        _id: null,
        _package_type: type,
        _name: name.trim(),
        _country_code: country === "GLOBAL" ? null : country,
        _currency: currency,
        _money_amount: Number(money),
        _coin_amount: Number(coins),
        _pearl_amount: Number(pearls),
        _usdt_amount: Number(usdt),
        _bonus_amount: Number(bonus),
        _fee_percentage: Number(fee),
        _discount_percentage: Number(discount),
        _agent_only: type === "usdt" || agentOnly,
        _enabled: true,
        _sort_order: 0,
      } as never);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("تم إنشاء الباقة");
      setOpen(false);
      done();
    },
    onError: (e: Error) => toast.error(e.message),
  });
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>
          <Plus className="ml-2 h-4 w-4" />
          إضافة باقة
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-3xl" dir="rtl">
        <DialogHeader>
          <DialogTitle>إنشاء باقة وتسعيرها</DialogTitle>
        </DialogHeader>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="اسم الباقة *" value={name} set={setName} />
          <div>
            <Label>نوع الباقة</Label>
            <Select value={type} onValueChange={(v) => setType(v as PackageType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {(Object.keys(TYPES) as PackageType[]).map((t) => (
                  <SelectItem key={t} value={t}>
                    {TYPES[t]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>الدولة</Label>
            <Select
              value={country}
              onValueChange={(v) => {
                setCountry(v);
                const c = COUNTRIES.find((x) => x.code === v);
                if (c) setCurrency(c.currency);
              }}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent className="max-h-72">
                <SelectItem value="GLOBAL">سعر عالمي بالدولار</SelectItem>
                {COUNTRIES.map((c) => (
                  <SelectItem key={c.code} value={c.code}>
                    {c.flag} {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <Field label="العملة" value={currency} set={(v) => setCurrency(v.toUpperCase())} />
          <Field label="المبلغ" value={money} set={setMoney} number />
          <Field label="عدد الكوينز" value={coins} set={setCoins} number />
          <Field label="عدد اللؤلؤ" value={pearls} set={setPearls} number />
          <Field label="قيمة USDT" value={usdt} set={setUsdt} number />
          <Field label="مكافأة إضافية" value={bonus} set={setBonus} number />
          <Field label="الرسوم %" value={fee} set={setFee} number />
          <Field label="الخصم %" value={discount} set={setDiscount} number />
          <label className="flex items-center justify-between rounded-lg border p-3">
            <span>للوكلاء فقط</span>
            <Switch
              checked={type === "usdt" || agentOnly}
              disabled={type === "usdt"}
              onCheckedChange={setAgentOnly}
            />
          </label>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            إلغاء
          </Button>
          <Button disabled={name.trim().length < 2 || save.isPending} onClick={() => save.mutate()}>
            {save.isPending && <Loader2 className="ml-2 h-4 w-4 animate-spin" />}حفظ الباقة
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
function Field({
  label,
  value,
  set,
  number,
}: {
  label: string;
  value: string;
  set: (v: string) => void;
  number?: boolean;
}) {
  return (
    <div>
      <Label>{label}</Label>
      <Input
        dir={number ? "ltr" : undefined}
        type={number ? "number" : "text"}
        min={number ? 0 : undefined}
        value={value}
        onChange={(e) => set(e.target.value)}
      />
    </div>
  );
}
