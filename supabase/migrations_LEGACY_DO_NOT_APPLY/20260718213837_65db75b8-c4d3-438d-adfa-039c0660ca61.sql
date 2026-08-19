
-- Evidence bucket RLS
DROP POLICY IF EXISTS "rde_bucket_read" ON storage.objects;
CREATE POLICY "rde_bucket_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'recharge-dispute-evidence'
    AND (public.has_permission(auth.uid(),'recharge_disputes.evidence.read')
         OR public.has_permission(auth.uid(),'recharge_disputes.manage'))
  );

DROP POLICY IF EXISTS "rde_bucket_insert" ON storage.objects;
CREATE POLICY "rde_bucket_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'recharge-dispute-evidence'
    AND (public.has_permission(auth.uid(),'recharge_disputes.evidence.create')
         OR public.has_permission(auth.uid(),'recharge_disputes.manage'))
  );

DROP POLICY IF EXISTS "rde_bucket_no_update" ON storage.objects;
CREATE POLICY "rde_bucket_no_update" ON storage.objects
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (bucket_id <> 'recharge-dispute-evidence')
  WITH CHECK (bucket_id <> 'recharge-dispute-evidence');

DROP POLICY IF EXISTS "rde_bucket_no_delete" ON storage.objects;
CREATE POLICY "rde_bucket_no_delete" ON storage.objects
  AS RESTRICTIVE FOR DELETE TO authenticated
  USING (bucket_id <> 'recharge-dispute-evidence');
