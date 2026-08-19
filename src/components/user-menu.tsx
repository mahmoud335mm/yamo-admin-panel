import { useNavigate } from "@tanstack/react-router";
import { LogOut, User as UserIcon } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { usePermissions } from "@/hooks/use-permissions";
import { useQueryClient } from "@tanstack/react-query";
import { logAudit } from "@/lib/audit";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem,
  DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Badge } from "@/components/ui/badge";

export function UserMenu() {
  const { user, roles } = usePermissions();
  const navigate = useNavigate();
  const qc = useQueryClient();

  const signOut = async () => {
    await logAudit("auth.signout");
    await qc.cancelQueries();
    qc.clear();
    await supabase.auth.signOut();
    navigate({ to: "/auth", replace: true });
  };

  const initials = (user?.email ?? "??").slice(0, 2).toUpperCase();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" className="gap-2 px-2">
          <Avatar className="h-7 w-7"><AvatarFallback>{initials}</AvatarFallback></Avatar>
          <div className="hidden text-right md:block">
            <div className="text-xs font-medium leading-tight">{user?.email}</div>
            <div className="text-[10px] text-muted-foreground">{roles[0] ?? "no role"}</div>
          </div>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel>
          <div className="text-xs">{user?.email}</div>
          <div className="mt-1 flex flex-wrap gap-1">
            {roles.map((r) => <Badge key={r} variant="secondary" className="text-[10px]">{r}</Badge>)}
          </div>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem disabled><UserIcon className="ml-2 h-4 w-4" />ملفي الشخصي</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={signOut} className="text-destructive focus:text-destructive">
          <LogOut className="ml-2 h-4 w-4" />تسجيل الخروج
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
