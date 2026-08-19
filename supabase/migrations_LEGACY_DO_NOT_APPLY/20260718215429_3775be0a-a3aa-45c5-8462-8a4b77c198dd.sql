
-- 5D-1.1: Blanket revoke anon EXECUTE from every SECURITY DEFINER function in public.
-- (Explicitly names all 14 currently-affected functions; also blanket-revokes to prevent regression.)

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM anon',
                   r.proname, r.args);
  END LOOP;
END $$;

-- Also revoke PUBLIC as a belt-and-braces guard on every SECDEF function.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
      AND has_function_privilege('public', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC',
                   r.proname, r.args);
  END LOOP;
END $$;

-- Chargeback provider identity completeness (constraint from spec §6).
ALTER TABLE public.recharge_disputes
  DROP CONSTRAINT IF EXISTS chk_disputes_chargeback_identity_complete;

ALTER TABLE public.recharge_disputes
  ADD CONSTRAINT chk_disputes_chargeback_identity_complete
  CHECK (
    provider_chargeback_id IS NULL
    OR (
      length(btrim(provider_chargeback_id)) > 0
      AND gateway_id IS NOT NULL
      AND gateway_mode IS NOT NULL
      AND gateway_mode IN ('test','live')
      AND chargeback_amount IS NOT NULL
      AND chargeback_currency IS NOT NULL
    )
  );

-- Legacy status preservation for future manual migrations.
ALTER TABLE public.recharge_disputes
  ADD COLUMN IF NOT EXISTS legacy_status_original text;

COMMENT ON COLUMN public.recharge_disputes.legacy_status_original IS
  'Preserved original status text prior to enum backfill. Do not overwrite once set.';
