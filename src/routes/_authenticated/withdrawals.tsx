import { createFileRoute, Navigate } from "@tanstack/react-router";

// دُمج قسم "السحب والشحن" داخل قسم "الشحن والسحب" الموحّد
export const Route = createFileRoute("/_authenticated/withdrawals")({
  component: () => <Navigate to="/finance/withdrawal-requests" replace />,
});
