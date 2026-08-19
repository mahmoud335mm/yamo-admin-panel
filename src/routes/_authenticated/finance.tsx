import { createFileRoute, Outlet } from "@tanstack/react-router";
import { PermissionGuard } from "@/components/permission-guard";

// Layout parent for /finance/*
export const Route = createFileRoute("/_authenticated/finance")({
  component: () => (
    <PermissionGuard permission="economy.read">
      <Outlet />
    </PermissionGuard>
  ),
});
