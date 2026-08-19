import { createFileRoute, redirect } from "@tanstack/react-router";
export const Route = createFileRoute("/_authenticated/finance/coin-prices")({
  beforeLoad: () => {
    throw redirect({ to: "/finance/packages" });
  },
});
