import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { AlertTriangle, Bell, CircleDollarSign, Loader2, WalletCards } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { yamoRpc } from "@/lib/yamo-admin";

type DashboardAlerts = {
  reports_open?: number;
  recharge_pending?: number;
  withdraw_pending?: number;
};

export function NotificationsMenu() {
  const alerts = useQuery({
    queryKey: ["yamo-admin", "header-alerts"],
    queryFn: () => yamoRpc<DashboardAlerts>("get_yamo_admin_dashboard"),
    refetchInterval: 60_000,
  });
  const data = alerts.data ?? {};
  const total =
    Number(data.reports_open ?? 0) +
    Number(data.recharge_pending ?? 0) +
    Number(data.withdraw_pending ?? 0);
  const items = [
    { label: "بلاغات مفتوحة", count: data.reports_open, to: "/reports", icon: AlertTriangle },
    {
      label: "طلبات شحن معلقة",
      count: data.recharge_pending,
      to: "/finance/recharge-requests",
      icon: CircleDollarSign,
    },
    {
      label: "طلبات سحب معلقة",
      count: data.withdraw_pending,
      to: "/finance/withdrawal-requests",
      icon: WalletCards,
    },
  ] as const;
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="relative" aria-label="تنبيهات التشغيل">
          <Bell className="h-4 w-4" />
          {total > 0 && (
            <span className="absolute left-1 top-1 h-2 w-2 rounded-full bg-destructive" />
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-80">
        <DropdownMenuLabel className="flex items-center justify-between">
          <span>تنبيهات التشغيل</span>
          <span className="text-xs text-muted-foreground">{total} معلّق</span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {alerts.isLoading ? (
          <div className="grid place-items-center p-6">
            <Loader2 className="h-5 w-5 animate-spin" />
          </div>
        ) : (
          items.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              className="flex items-center justify-between rounded-md px-3 py-2 text-sm hover:bg-muted"
            >
              <span className="flex items-center gap-2">
                <item.icon className="h-4 w-4 text-muted-foreground" />
                {item.label}
              </span>
              <span className="font-bold">{Number(item.count ?? 0)}</span>
            </Link>
          ))
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
