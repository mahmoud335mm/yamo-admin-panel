import { Link, useRouterState } from "@tanstack/react-router";
import { navItems, type NavItem } from "@/lib/nav-config";
import { usePermissions } from "@/hooks/use-permissions";
import {
  Sidebar, SidebarContent, SidebarGroup, SidebarGroupContent, SidebarGroupLabel,
  SidebarMenu, SidebarMenuButton, SidebarMenuItem, SidebarMenuSub, SidebarMenuSubButton, SidebarMenuSubItem,
  SidebarHeader, SidebarFooter, useSidebar,
} from "@/components/ui/sidebar";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Sparkles, ChevronLeft } from "lucide-react";

function isChildActive(pathname: string, to: string) {
  return pathname === to || pathname.startsWith(to + "/");
}

export function AppSidebar() {
  const { state } = useSidebar();
  const collapsed = state === "collapsed";
  const pathname = useRouterState({ select: (r) => r.location.pathname });
  const { has } = usePermissions();

  const renderItem = (item: NavItem) => {
    const allowed = !item.permission || has(item.permission);
    if (!allowed) return null;

    // مجموعة قابلة للطي
    if (item.children && item.children.length > 0) {
      const visibleChildren = item.children.filter((c) => !c.permission || has(c.permission));
      if (visibleChildren.length === 0) return null;
      const anyActive = visibleChildren.some((c) => isChildActive(pathname, c.to));
      const Icon = item.icon;

      return (
        <Collapsible key={item.to} defaultOpen={anyActive} className="group/collapsible">
          <SidebarMenuItem>
            <CollapsibleTrigger asChild>
              <SidebarMenuButton isActive={anyActive} tooltip={item.labelAr}>
                <Icon className="h-4 w-4 shrink-0" />
                {!collapsed && (
                  <>
                    <span className="flex-1 text-right">{item.labelAr}</span>
                    <ChevronLeft className="h-3 w-3 transition-transform group-data-[state=open]/collapsible:-rotate-90" />
                  </>
                )}
              </SidebarMenuButton>
            </CollapsibleTrigger>
            {!collapsed && (
              <CollapsibleContent>
                <SidebarMenuSub>
                  {visibleChildren.map((child) => {
                    const active = isChildActive(pathname, child.to);
                    const ChildIcon = child.icon;
                    return (
                      <SidebarMenuSubItem key={child.to}>
                        <SidebarMenuSubButton asChild isActive={active}>
                          <Link to={child.to} className="flex items-center gap-2">
                            <ChildIcon className="h-3.5 w-3.5 shrink-0 opacity-70" />
                            <span>{child.labelAr}</span>
                          </Link>
                        </SidebarMenuSubButton>
                      </SidebarMenuSubItem>
                    );
                  })}
                </SidebarMenuSub>
              </CollapsibleContent>
            )}
          </SidebarMenuItem>
        </Collapsible>
      );
    }

    // عنصر مفرد
    const active = isChildActive(pathname, item.to);
    const Icon = item.icon;
    return (
      <SidebarMenuItem key={item.to}>
        <SidebarMenuButton asChild isActive={active} tooltip={item.labelAr}>
          <Link to={item.to} className="flex items-center gap-2">
            <Icon className="h-4 w-4 shrink-0" />
            {!collapsed && <span>{item.labelAr}</span>}
          </Link>
        </SidebarMenuButton>
      </SidebarMenuItem>
    );
  };

  return (
    <Sidebar collapsible="icon" side="right">
      <SidebarHeader className="border-b">
        <div className="flex items-center gap-2 px-2 py-2">
          <div className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-gradient-to-br from-orange-500 to-purple-600 text-white">
            <Sparkles className="h-4 w-4" />
          </div>
          {!collapsed && (
            <div className="flex flex-col leading-tight">
              <span className="text-sm font-bold">يامو شات</span>
              <span className="text-[10px] text-muted-foreground">Admin Console</span>
            </div>
          )}
        </div>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>القوائم</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>{navItems.map(renderItem)}</SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter className="border-t">
        {!collapsed && (
          <div className="px-2 py-2 text-[10px] text-muted-foreground">
            © Yamo Chat · v1.0
          </div>
        )}
      </SidebarFooter>
    </Sidebar>
  );
}
