import { useRouterState } from "@tanstack/react-router";
import { navItems, flatNavItems } from "@/lib/nav-config";
import { ChevronLeft } from "lucide-react";
import { useAdminLanguage } from "@/lib/admin-language";

export function Breadcrumbs() {
  const pathname = useRouterState({ select: (r) => r.location.pathname });
  const language = useAdminLanguage();

  // ابحث عن العنصر الحالي (child) والوالد إن وجد
  const leaf = flatNavItems.find((n) => pathname === n.to || pathname.startsWith(n.to + "/"));
  const parent = navItems.find(
    (p) => p.children && p.children.length > 0 && p.children.some((c) => c.to === leaf?.to),
  );

  return (
    <nav className="flex items-center gap-1 text-xs text-muted-foreground">
      <span>{language === "ar" ? "لوحة التحكم" : "Dashboard"}</span>
      {parent && parent.to !== leaf?.to && (
        <>
          <ChevronLeft className="h-3 w-3" />
          <span>{language === "ar" ? parent.labelAr : parent.labelEn}</span>
        </>
      )}
      {leaf && (
        <>
          <ChevronLeft className="h-3 w-3" />
          <span className="text-foreground">{language === "ar" ? leaf.labelAr : leaf.labelEn}</span>
        </>
      )}
    </nav>
  );
}
