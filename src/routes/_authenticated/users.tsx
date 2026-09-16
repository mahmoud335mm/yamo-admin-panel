import { createFileRoute, Outlet, useRouterState } from "@tanstack/react-router";
import { PermissionGuard } from "@/components/permission-guard";
import { UsersCommandCenter } from "@/components/users-command-center";
export const Route = createFileRoute("/_authenticated/users")({
  component: UsersPage,
});
function UsersPage() {
  const detail = useRouterState({ select: (state) => state.matches.some((match) => match.routeId === "/_authenticated/users/$id") });
  return <PermissionGuard permission="users.read">{detail ? <Outlet /> : <UsersCommandCenter />}</PermissionGuard>;
}
