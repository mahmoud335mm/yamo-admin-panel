import type { ReactNode } from "react";
import { usePermissions } from "@/hooks/use-permissions";
import { ShieldAlert } from "lucide-react";

export function PermissionGuard({ permission, children }: { permission: string; children: ReactNode }) {
  const { isLoading, has } = usePermissions();
  if (isLoading) {
    return <div className="p-8 text-sm text-muted-foreground">جاري التحقق من الصلاحيات…</div>;
  }
  if (!has(permission)) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 p-16 text-center">
        <ShieldAlert className="h-10 w-10 text-destructive" />
        <h2 className="text-lg font-semibold">لا تملك صلاحية الوصول</h2>
        <p className="text-sm text-muted-foreground">تحتاج إلى الصلاحية: <code className="rounded bg-muted px-1.5 py-0.5">{permission}</code></p>
      </div>
    );
  }
  return <>{children}</>;
}
