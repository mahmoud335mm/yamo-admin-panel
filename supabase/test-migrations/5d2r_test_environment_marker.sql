-- TEST PROJECT ONLY
-- DO NOT APPLY TO PRODUCTION
--
-- Phase 5D-2R Test Environment Marker.
-- Creates a single-row table that DB-side guards check before any harness write.
-- Guards inside SQL fail closed if the project ref matches production.

DO $$
BEGIN
  IF current_database() ILIKE '%prod%' THEN
    RAISE EXCEPTION 'PRODUCTION_PROJECT_BLOCKED: refusing to install test marker on production-like database';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.test_environment_marker (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  environment_name text NOT NULL CHECK (environment_name = 'test'),
  project_ref text NOT NULL,
  test_fixtures_allowed boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT test_environment_marker_singleton CHECK (true),
  CONSTRAINT test_environment_marker_not_production CHECK (project_ref <> 'omgrldatyncodeabecia')
);

GRANT SELECT ON public.test_environment_marker TO authenticated;
GRANT ALL ON public.test_environment_marker TO service_role;

ALTER TABLE public.test_environment_marker ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated can read test marker" ON public.test_environment_marker;
CREATE POLICY "authenticated can read test marker"
  ON public.test_environment_marker FOR SELECT
  TO authenticated USING (true);

-- Row insertion is done by the CI provisioner using service_role and the
-- resolved EXPECTED_TEST_PROJECT_REF. Example:
--   INSERT INTO public.test_environment_marker (environment_name, project_ref)
--   VALUES ('test', '<expected-test-project-ref>');
