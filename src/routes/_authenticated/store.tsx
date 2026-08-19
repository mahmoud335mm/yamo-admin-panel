import { createFileRoute, Navigate } from "@tanstack/react-router";

export const Route = createFileRoute("/_authenticated/store")({
  component: () => <Navigate to="/gifts" replace />,
});
