import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import {
  Activity,
  BadgeDollarSign,
  Building2,
  CircleDollarSign,
  DoorOpen,
  Gift,
  Loader2,
  Mars,
  ShieldCheck,
  TrendingDown,
  TrendingUp,
  UserCheck,
  Users,
  Venus,
  WalletCards,
} from "lucide-react";
import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { yamoRpc } from "@/lib/yamo-admin";

type TrendPoint = {
  day: string;
  revenue: number;
  expenses: number;
  profit: number;
  new_users: number;
};
type DashboardData = {
  users_total?: number;
  males?: number;
  females?: number;
  agencies?: number;
  bd_managers?: number;
  charging_agencies?: number;
  rooms_total?: number;
  rooms_live?: number;
  admins_active?: number;
  reports_open?: number;
  support_open?: number;
  verification_pending?: number;
  recharge_pending?: number;
  withdraw_pending?: number;
  gift_coins_today?: number;
  currency?: string;
  revenue_today?: number;
  expenses_today?: number;
  profit_today?: number;
  profit_period?: number;
  trend?: TrendPoint[];
};
const number = new Intl.NumberFormat("ar-EG", { maximumFractionDigits: 0 });
const money = new Intl.NumberFormat("ar-EG", { maximumFractionDigits: 2 });

export const Route = createFileRoute("/_authenticated/dashboard")({ component: Dashboard });

function Dashboard() {
  const [days, setDays] = useState(30);
  const q = useQuery({
    queryKey: ["yamo-dashboard-v2", days],
    queryFn: () => yamoRpc<DashboardData>("get_yamo_admin_dashboard_v2", { p_days: days }),
    refetchInterval: 60_000,
  });
  const d = q.data ?? {};
  const currency = d.currency ?? "EGP";
  const profitToday = Number(d.profit_today ?? 0);
  const periodProfit = Number(d.profit_period ?? 0);
  const stats = [
    ["إجمالي المستخدمين", d.users_total, Users, "text-violet-500"],
    ["الذكور", d.males, Mars, "text-blue-500"],
    ["الإناث", d.females, Venus, "text-pink-500"],
    ["الوكالات", d.agencies, Building2, "text-orange-500"],
    ["مديرو BD", d.bd_managers, UserCheck, "text-cyan-500"],
    ["وكالات الشحن", d.charging_agencies, WalletCards, "text-emerald-500"],
    ["الغرف", d.rooms_total, DoorOpen, "text-indigo-500"],
    ["الغرف النشطة الآن", d.rooms_live, Activity, "text-green-500"],
    ["المسؤولون النشطون", d.admins_active, ShieldCheck, "text-amber-500"],
    ["هدايا اليوم بالكوينز", d.gift_coins_today, Gift, "text-fuchsia-500"],
  ] as const;
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black">مركز قيادة Yamo Chat</h1>
          <p className="text-sm text-muted-foreground">مؤشرات مباشرة تتحدث تلقائيًا كل دقيقة</p>
        </div>
        <Badge variant="outline" className="gap-2 px-3 py-1.5">
          <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-500" /> مباشر
        </Badge>
      </div>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <MoneyCard
          title="دخل اليوم"
          value={d.revenue_today}
          currency={currency}
          icon={CircleDollarSign}
          tone="positive"
        />
        <MoneyCard
          title="مصروفات اليوم"
          value={d.expenses_today}
          currency={currency}
          icon={BadgeDollarSign}
          tone="negative"
        />
        <MoneyCard
          title="صافي ربح اليوم"
          value={profitToday}
          currency={currency}
          icon={profitToday >= 0 ? TrendingUp : TrendingDown}
          tone={profitToday >= 0 ? "positive" : "negative"}
          signed
        />
        <MoneyCard
          title={`صافي آخر ${days} يوم`}
          value={periodProfit}
          currency={currency}
          icon={periodProfit >= 0 ? TrendingUp : TrendingDown}
          tone={periodProfit >= 0 ? "positive" : "negative"}
          signed
        />
      </div>
      <Card className="overflow-hidden">
        <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-3">
          <div>
            <CardTitle>حركة الأرباح والمصروفات</CardTitle>
            <p className="mt-1 text-xs text-muted-foreground">
              القيم بعملة {currency} — الصعود أخضر والنزول أحمر
            </p>
          </div>
          <div className="flex gap-1 rounded-lg bg-muted p-1">
            {[7, 30, 90].map((value) => (
              <Button
                key={value}
                size="sm"
                variant={days === value ? "default" : "ghost"}
                onClick={() => setDays(value)}
              >
                {value} يوم
              </Button>
            ))}
          </div>
        </CardHeader>
        <CardContent className="h-80 px-2 sm:px-6">
          {q.isLoading ? (
            <div className="grid h-full place-items-center">
              <Loader2 className="h-7 w-7 animate-spin" />
            </div>
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={d.trend ?? []} margin={{ top: 12, right: 8, left: 8, bottom: 0 }}>
                <defs>
                  <linearGradient id="revenueGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#22c55e" stopOpacity={0.35} />
                    <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="expenseGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#ef4444" stopOpacity={0.28} />
                    <stop offset="95%" stopColor="#ef4444" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="4 4" vertical={false} opacity={0.25} />
                <XAxis dataKey="day" tickLine={false} axisLine={false} fontSize={11} />
                <YAxis
                  tickLine={false}
                  axisLine={false}
                  fontSize={11}
                  tickFormatter={(v) => number.format(Number(v))}
                />
                <Tooltip
                  formatter={(v) => `${money.format(Number(v))} ${currency}`}
                  contentStyle={{ borderRadius: 12 }}
                />
                <Legend />
                <Area
                  name="الدخل"
                  type="monotone"
                  dataKey="revenue"
                  stroke="#22c55e"
                  strokeWidth={3}
                  fill="url(#revenueGradient)"
                />
                <Area
                  name="المصروفات"
                  type="monotone"
                  dataKey="expenses"
                  stroke="#ef4444"
                  strokeWidth={3}
                  fill="url(#expenseGradient)"
                />
                <Area
                  name="الصافي"
                  type="monotone"
                  dataKey="profit"
                  stroke="#8b5cf6"
                  strokeWidth={2}
                  fill="transparent"
                />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        {stats.map(([label, value, Icon, color]) => (
          <Card key={label} className="transition-transform hover:-translate-y-0.5">
            <CardContent className="flex items-center justify-between p-4">
              <div>
                <div className="text-xs text-muted-foreground">{label}</div>
                <div className="mt-1 text-2xl font-black">
                  {q.isLoading ? "…" : number.format(Number(value ?? 0))}
                </div>
              </div>
              <div className="rounded-xl bg-muted p-2.5">
                <Icon className={`h-5 w-5 ${color}`} />
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
      <div className="grid gap-4 md:grid-cols-3 xl:grid-cols-6">
        <QueueCard label="بلاغات مفتوحة" value={d.reports_open} />
        <QueueCard label="تذاكر الدعم" value={d.support_open} />
        <QueueCard label="طلبات التحقق" value={d.verification_pending} />
        <QueueCard label="شحن معلّق" value={d.recharge_pending} />
        <QueueCard label="سحب معلّق" value={d.withdraw_pending} />
        <QueueCard
          label="مستخدمون جدد"
          value={(d.trend ?? []).reduce((sum, row) => sum + Number(row.new_users ?? 0), 0)}
        />
      </div>
      {q.error && (
        <Card className="border-destructive/30">
          <CardContent className="p-5 text-sm text-destructive">
            {(q.error as Error).message}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function MoneyCard({
  title,
  value,
  currency,
  icon: Icon,
  tone,
  signed = false,
}: {
  title: string;
  value?: number;
  currency: string;
  icon: typeof TrendingUp;
  tone: "positive" | "negative";
  signed?: boolean;
}) {
  const numeric = Number(value ?? 0);
  const color = tone === "positive" ? "text-emerald-500" : "text-red-500";
  return (
    <Card className="relative overflow-hidden">
      <div
        className={`absolute inset-x-0 top-0 h-1 ${tone === "positive" ? "bg-emerald-500" : "bg-red-500"}`}
      />
      <CardContent className="flex items-center justify-between p-5">
        <div>
          <div className="text-sm text-muted-foreground">{title}</div>
          <div className={`mt-2 text-2xl font-black ${color}`}>
            {signed && numeric > 0 ? "+" : ""}
            {money.format(numeric)} <span className="text-xs">{currency}</span>
          </div>
        </div>
        <div className="rounded-2xl bg-muted p-3">
          <Icon className={`h-6 w-6 ${color}`} />
        </div>
      </CardContent>
    </Card>
  );
}
function QueueCard({ label, value }: { label: string; value?: number }) {
  const count = Number(value ?? 0);
  return (
    <Card>
      <CardContent className="p-4 text-center">
        <div
          className={`text-2xl font-black ${count > 0 ? "text-orange-500" : "text-emerald-500"}`}
        >
          {number.format(count)}
        </div>
        <div className="mt-1 text-xs text-muted-foreground">{label}</div>
      </CardContent>
    </Card>
  );
}
