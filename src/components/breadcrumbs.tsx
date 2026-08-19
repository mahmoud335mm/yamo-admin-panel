import { useRouterState } from "@tanstack/react-router";
import { navItems, flatNavItems } from "@/lib/nav-config";
import { ChevronLeft } from "lucide-react";

export function Breadcrumbs() {
  const pathname = useRouterState({ select: (r) => r.location.pathname });

  // ابحث عن العنصر الحالي (child) والوالد إن وجد
  const leaf = flatNavItems.find((n) => pathname === n.to || pathname.startsWith(n.to + "/"));
  const parent = navItems.find(
    (p) => p.children && p.children.length > 0 && p.children.some((c) => c.to === leaf?.to),
  );

  return (
    <nav className="flex items-center gap-1 text-xs text-muted-foreground">
      <span>لوحة التحكم</span>
      {parent && parent.to !== leaf?.to && (
        <>
          <ChevronLeft className="h-3 w-3" />
          <span>{parent.labelAr}</span>
        </>
      )}
      {leaf && (
        <>
          <ChevronLeft className="h-3 w-3" />
          <span className="text-foreground">{leaf.labelAr}</span>
        </>
      )}
    </nav>
  );
}
