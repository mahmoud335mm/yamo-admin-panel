import { createFileRoute, Outlet, redirect, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { SidebarProvider, SidebarInset, SidebarTrigger } from "@/components/ui/sidebar";
import { AppSidebar } from "@/components/app-sidebar";
import { Separator } from "@/components/ui/separator";
import { ThemeToggle } from "@/components/theme-toggle";
import { LanguageToggle } from "@/components/language-toggle";
import { UserMenu } from "@/components/user-menu";
import { GlobalSearch } from "@/components/global-search";
import { NotificationsMenu } from "@/components/notifications-menu";
import { Breadcrumbs } from "@/components/breadcrumbs";
import { Toaster } from "@/components/ui/sonner";
import { getYamoAdminMe } from "@/lib/yamo-admin";
import { useAdminLanguage } from "@/lib/admin-language";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    const { data } = await supabase.auth.getUser();
    if (!data.user) throw redirect({ to: "/auth" });
    try {
      const admin = await getYamoAdminMe();
      return { user: data.user, admin };
    } catch {
      await supabase.auth.signOut();
      throw redirect({ to: "/auth", search: { denied: "1" } as never });
    }
  },
  component: AuthenticatedLayout,
});

function AuthenticatedLayout() {
  const navigate = useNavigate();
  const language = useAdminLanguage();
  useEffect(() => {
    const language = window.localStorage.getItem("yamo-admin-language") === "en" ? "en" : "ar";
    document.documentElement.lang = language;
    document.documentElement.dir = language === "ar" ? "rtl" : "ltr";
    document.body.dataset.adminLanguage = language;
    const { data: sub } = supabase.auth.onAuthStateChange((e, s) => {
      if (e === "SIGNED_OUT" || !s) navigate({ to: "/auth", replace: true });
    });
    return () => sub.subscription.unsubscribe();
  }, [navigate]);

  return (
    <div dir={language === "ar" ? "rtl" : "ltr"}>
      <SidebarProvider>
        <AppSidebar />
        <SidebarInset>
          <header className="yamo-topbar sticky top-0 z-30 flex h-16 items-center gap-2 border-b px-4 backdrop-blur-xl">
            <SidebarTrigger />
            <Separator orientation="vertical" className="h-5" />
            <Breadcrumbs />
            <div className="mr-auto flex items-center gap-2">
              <GlobalSearch />
              <NotificationsMenu />
              <LanguageToggle />
              <ThemeToggle />
              <UserMenu />
            </div>
          </header>
          <main className="yamo-workspace min-h-[calc(100vh-4rem)] p-4 md:p-6 xl:p-8">
            <Outlet />
          </main>
        </SidebarInset>
      </SidebarProvider>
      <Toaster position="top-center" richColors />
    </div>
  );
}
