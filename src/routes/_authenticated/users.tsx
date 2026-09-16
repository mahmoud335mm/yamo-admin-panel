import { createFileRoute } from "@tanstack/react-router";
import { PermissionGuard } from "@/components/permission-guard";
import { UsersCommandCenter } from "@/components/users-command-center";
export const Route = createFileRoute("/_authenticated/users")({
  component: () => <PermissionGuard permission="users.read"><UsersCommandCenter /></PermissionGuard>,
});
