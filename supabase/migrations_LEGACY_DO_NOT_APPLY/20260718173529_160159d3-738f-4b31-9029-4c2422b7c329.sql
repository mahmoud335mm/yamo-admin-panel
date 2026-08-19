
DROP VIEW IF EXISTS public.payment_gateway_stats;
CREATE VIEW public.payment_gateway_stats WITH (security_invoker=true) AS
SELECT
  g.id AS gateway_id,
  (SELECT count(*) FROM public.payment_webhooks w WHERE w.gateway_id=g.id AND w.processed) AS success_count,
  (SELECT count(*) FROM public.payment_webhooks w WHERE w.gateway_id=g.id AND w.processing_error IS NOT NULL) AS failure_count,
  (SELECT max(received_at) FROM public.payment_webhooks w WHERE w.gateway_id=g.id) AS last_webhook_at,
  (SELECT count(*) FROM public.payment_failures f WHERE f.gateway_id=g.id) AS total_failures
FROM public.payment_gateways g;
GRANT SELECT ON public.payment_gateway_stats TO authenticated;

REVOKE EXECUTE ON FUNCTION public.create_payment_gateway(text,text,text,payment_gateway_mode,text,text[],text[],numeric,numeric,numeric,numeric,integer,text,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.update_payment_gateway(uuid,jsonb,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.enable_payment_gateway(uuid,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.disable_payment_gateway(uuid,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.change_payment_gateway_mode(uuid,payment_gateway_mode,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.update_gateway_country_config(uuid,text,numeric,numeric,numeric,numeric,boolean) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.update_gateway_currency_config(uuid,text,numeric,boolean) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.record_gateway_health_check(uuid,payment_health_status,integer,integer,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.mark_gateway_secret_configured(uuid,text,text,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.resolve_payment_failure(uuid,text) FROM anon, public;

GRANT EXECUTE ON FUNCTION public.create_payment_gateway(text,text,text,payment_gateway_mode,text,text[],text[],numeric,numeric,numeric,numeric,integer,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_payment_gateway(uuid,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enable_payment_gateway(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disable_payment_gateway(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_payment_gateway_mode(uuid,payment_gateway_mode,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_gateway_country_config(uuid,text,numeric,numeric,numeric,numeric,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_gateway_currency_config(uuid,text,numeric,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_gateway_health_check(uuid,payment_health_status,integer,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_gateway_secret_configured(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_payment_failure(uuid,text) TO authenticated;
