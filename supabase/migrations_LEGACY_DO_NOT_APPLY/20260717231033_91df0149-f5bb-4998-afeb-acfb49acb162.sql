
-- Same as before with correct admin_role name

DO $$ BEGIN CREATE TYPE public.charging_agency_status AS ENUM ('pending','active','suspended','under_review','closed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.charging_agent_role AS ENUM ('charging_agency_owner','charging_agency_deputy','charging_agent','charging_accountant','charging_supervisor','charging_region_manager','charging_country_manager'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.charging_agent_status AS ENUM ('active','suspended','inactive'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.charging_txn_status AS ENUM ('pending','completed','reversed','failed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.pearl_purchase_status AS ENUM ('draft','pending_user_confirmation','pending_agent_payment','payment_submitted','pending_user_receipt_confirmation','pending_admin_review','completed','rejected','cancelled','disputed','reversed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.wallet_adjustment_kind AS ENUM ('coin_credit','coin_debit','pearl_credit','pearl_debit'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.wallet_adjustment_status AS ENUM ('pending','approved','rejected','applied','reversed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.charging_agencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_id text UNIQUE NOT NULL DEFAULT ('CA-' || substr(replace(gen_random_uuid()::text,'-',''),1,10)),
  name text NOT NULL, logo_url text, cover_url text,
  country text, city text, default_currency text DEFAULT 'USD',
  phone text, email text,
  owner_user_id uuid REFERENCES public.profiles(id),
  deputy_user_id uuid REFERENCES public.profiles(id),
  status public.charging_agency_status NOT NULL DEFAULT 'pending',
  level_id smallint DEFAULT 1,
  commission_rate numeric(6,4) DEFAULT 0,
  daily_coin_transfer_limit bigint DEFAULT 100000000,
  monthly_coin_transfer_limit bigint DEFAULT 3000000000,
  daily_pearl_transfer_limit bigint DEFAULT 10000000,
  monthly_pearl_transfer_limit bigint DEFAULT 300000000,
  min_coin_transfer bigint DEFAULT 1000, max_coin_transfer bigint DEFAULT 100000000,
  min_pearl_transfer bigint DEFAULT 100, max_pearl_transfer bigint DEFAULT 10000000,
  can_buy_pearls boolean NOT NULL DEFAULT true,
  can_sell_coins boolean NOT NULL DEFAULT true,
  can_exchange_pearls_to_coins boolean NOT NULL DEFAULT true,
  can_transfer_to_agents boolean NOT NULL DEFAULT true,
  can_receive_from_agents boolean NOT NULL DEFAULT true,
  supported_payment_methods jsonb NOT NULL DEFAULT '[]'::jsonb,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, created_by uuid, updated_by uuid
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_agencies TO authenticated;
GRANT ALL ON public.charging_agencies TO service_role;
ALTER TABLE public.charging_agencies ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_agency_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id uuid NOT NULL REFERENCES public.charging_agencies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  member_role public.charging_agent_role NOT NULL DEFAULT 'charging_agent',
  status public.charging_agent_status NOT NULL DEFAULT 'active',
  assigned_by uuid, assigned_at timestamptz NOT NULL DEFAULT now(), removed_at timestamptz,
  UNIQUE (agency_id, user_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS charging_agency_members_active_user ON public.charging_agency_members(user_id) WHERE status = 'active';
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_agency_members TO authenticated;
GRANT ALL ON public.charging_agency_members TO service_role;
ALTER TABLE public.charging_agency_members ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_agent_settings (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  agency_id uuid REFERENCES public.charging_agencies(id) ON DELETE SET NULL,
  status public.charging_agent_status NOT NULL DEFAULT 'active',
  daily_coin_limit bigint DEFAULT 50000000, monthly_coin_limit bigint DEFAULT 1500000000,
  daily_pearl_limit bigint DEFAULT 5000000, monthly_pearl_limit bigint DEFAULT 150000000,
  min_coin_transfer bigint DEFAULT 1000, max_coin_transfer bigint DEFAULT 50000000,
  min_pearl_transfer bigint DEFAULT 100, max_pearl_transfer bigint DEFAULT 5000000,
  can_sell_coins boolean NOT NULL DEFAULT true,
  can_buy_pearls boolean NOT NULL DEFAULT true,
  can_transfer_to_agents boolean NOT NULL DEFAULT true,
  can_exchange_pearls_to_coins boolean NOT NULL DEFAULT true,
  confirmation_pin_hash text,
  activated_at timestamptz NOT NULL DEFAULT now(), activated_by uuid,
  suspended_at timestamptz, suspended_by uuid, suspend_reason text,
  deactivated_at timestamptz, deactivated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_agent_settings TO authenticated;
GRANT ALL ON public.charging_agent_settings TO service_role;
ALTER TABLE public.charging_agent_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_coin_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL DEFAULT ('YC-COIN-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  agent_user_id uuid NOT NULL REFERENCES public.profiles(id),
  agency_id uuid REFERENCES public.charging_agencies(id),
  recipient_user_id uuid NOT NULL REFERENCES public.profiles(id),
  recipient_is_agent boolean NOT NULL DEFAULT false,
  amount bigint NOT NULL CHECK (amount > 0),
  sale_price numeric(14,4), currency text,
  payment_method_id uuid, payment_reference text, receipt_url text, note text,
  commission_amount bigint DEFAULT 0,
  status public.charging_txn_status NOT NULL DEFAULT 'pending',
  idempotency_key text UNIQUE,
  message_id uuid,
  reversed_by uuid REFERENCES public.charging_coin_transfers(id),
  created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_ccoin_agent ON public.charging_coin_transfers(agent_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ccoin_recipient ON public.charging_coin_transfers(recipient_user_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_coin_transfers TO authenticated;
GRANT ALL ON public.charging_coin_transfers TO service_role;
ALTER TABLE public.charging_coin_transfers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_coin_transfer_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  original_transfer_id uuid NOT NULL UNIQUE REFERENCES public.charging_coin_transfers(id),
  reason text NOT NULL, reversed_by uuid NOT NULL, reversed_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.charging_coin_transfer_reversals TO authenticated;
GRANT ALL ON public.charging_coin_transfer_reversals TO service_role;
ALTER TABLE public.charging_coin_transfer_reversals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_pearl_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL DEFAULT ('YC-PEARL-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  from_user_id uuid NOT NULL REFERENCES public.profiles(id),
  to_user_id uuid NOT NULL REFERENCES public.profiles(id),
  amount bigint NOT NULL CHECK (amount > 0),
  note text,
  status public.charging_txn_status NOT NULL DEFAULT 'pending',
  idempotency_key text UNIQUE, message_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_cpearl_from ON public.charging_pearl_transfers(from_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cpearl_to ON public.charging_pearl_transfers(to_user_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_pearl_transfers TO authenticated;
GRANT ALL ON public.charging_pearl_transfers TO service_role;
ALTER TABLE public.charging_pearl_transfers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_pearl_transfer_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  original_transfer_id uuid NOT NULL UNIQUE REFERENCES public.charging_pearl_transfers(id),
  reason text NOT NULL, reversed_by uuid NOT NULL, reversed_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.charging_pearl_transfer_reversals TO authenticated;
GRANT ALL ON public.charging_pearl_transfer_reversals TO service_role;
ALTER TABLE public.charging_pearl_transfer_reversals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  agency_id uuid REFERENCES public.charging_agencies(id) ON DELETE SET NULL,
  preferred_agent_id uuid REFERENCES public.profiles(id),
  name text, phone text, country text,
  coin_purchase_count int DEFAULT 0, total_coins_purchased bigint DEFAULT 0,
  total_coin_amount_paid numeric(16,4) DEFAULT 0,
  pearl_sale_count int DEFAULT 0, total_pearls_sold bigint DEFAULT 0,
  total_pearl_amount_received numeric(16,4) DEFAULT 0,
  last_transaction_at timestamptz, average_order_value numeric(16,4) DEFAULT 0,
  debt_balance bigint DEFAULT 0, internal_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (agency_id, user_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_customers TO authenticated;
GRANT ALL ON public.charging_customers TO service_role;
ALTER TABLE public.charging_customers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_price_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country text, currency text NOT NULL DEFAULT 'USD',
  agency_id uuid REFERENCES public.charging_agencies(id) ON DELETE CASCADE,
  agent_level_id smallint, operation text NOT NULL,
  tier_from bigint NOT NULL DEFAULT 0, tier_to bigint,
  unit_price numeric(14,6) NOT NULL,
  fee_percentage numeric(6,4) DEFAULT 0,
  commission_percentage numeric(6,4) DEFAULT 0,
  discount_percentage numeric(6,4) DEFAULT 0,
  status text NOT NULL DEFAULT 'draft',
  starts_at timestamptz, ends_at timestamptz,
  version int NOT NULL DEFAULT 1, created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_price_rules TO authenticated;
GRANT ALL ON public.charging_price_rules TO service_role;
ALTER TABLE public.charging_price_rules ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id uuid REFERENCES public.charging_agencies(id) ON DELETE CASCADE,
  agent_user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  method_code text NOT NULL, display_name text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  currency text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charging_payment_methods TO authenticated;
GRANT ALL ON public.charging_payment_methods TO service_role;
ALTER TABLE public.charging_payment_methods ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pearl_purchase_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL DEFAULT ('YC-PPR-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  agent_user_id uuid NOT NULL REFERENCES public.profiles(id),
  user_id uuid NOT NULL REFERENCES public.profiles(id),
  agency_id uuid REFERENCES public.charging_agencies(id),
  pearl_amount bigint NOT NULL CHECK (pearl_amount > 0),
  price_amount numeric(14,4) NOT NULL,
  currency text NOT NULL DEFAULT 'USD',
  status public.pearl_purchase_status NOT NULL DEFAULT 'pending_user_confirmation',
  idempotency_key text UNIQUE,
  user_confirmed_at timestamptz,
  payment_submitted_at timestamptz, payment_proof_url text,
  user_receipt_confirmed_at timestamptz,
  admin_reviewed_by uuid, admin_reviewed_at timestamptz, admin_note text,
  completed_at timestamptz, message_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ppr_agent ON public.pearl_purchase_requests(agent_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ppr_user ON public.pearl_purchase_requests(user_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pearl_purchase_requests TO authenticated;
GRANT ALL ON public.pearl_purchase_requests TO service_role;
ALTER TABLE public.pearl_purchase_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pearl_purchase_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.pearl_purchase_requests(id) ON DELETE CASCADE,
  method_code text, reference text, proof_url text,
  amount numeric(14,4), currency text, submitted_by uuid,
  submitted_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.pearl_purchase_payments TO authenticated;
GRANT ALL ON public.pearl_purchase_payments TO service_role;
ALTER TABLE public.pearl_purchase_payments ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pearl_purchase_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  original_request_id uuid NOT NULL UNIQUE REFERENCES public.pearl_purchase_requests(id),
  reason text NOT NULL, reversed_by uuid NOT NULL, reversed_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.pearl_purchase_reversals TO authenticated;
GRANT ALL ON public.pearl_purchase_reversals TO service_role;
ALTER TABLE public.pearl_purchase_reversals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pearl_coin_exchange_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country text, agency_id uuid REFERENCES public.charging_agencies(id) ON DELETE CASCADE,
  agent_level_id smallint, pearl_amount_from bigint NOT NULL DEFAULT 0,
  pearl_amount_to bigint,
  coins_per_pearl numeric(10,4) NOT NULL CHECK (coins_per_pearl > 0),
  fee_percentage numeric(6,4) DEFAULT 0,
  min_exchange bigint DEFAULT 100, max_exchange bigint DEFAULT 10000000,
  daily_limit bigint DEFAULT 100000000, monthly_limit bigint DEFAULT 3000000000,
  status text NOT NULL DEFAULT 'draft',
  starts_at timestamptz, ends_at timestamptz,
  version int NOT NULL DEFAULT 1, created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pearl_coin_exchange_rates TO authenticated;
GRANT ALL ON public.pearl_coin_exchange_rates TO service_role;
ALTER TABLE public.pearl_coin_exchange_rates ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pearl_coin_exchanges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL DEFAULT ('YC-EXC-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  agent_user_id uuid NOT NULL REFERENCES public.profiles(id),
  agency_id uuid REFERENCES public.charging_agencies(id),
  rate_id uuid REFERENCES public.pearl_coin_exchange_rates(id),
  pearl_amount bigint NOT NULL CHECK (pearl_amount > 0),
  coins_amount bigint NOT NULL CHECK (coins_amount > 0),
  fee_amount bigint DEFAULT 0,
  applied_rate numeric(10,4) NOT NULL,
  status public.charging_txn_status NOT NULL DEFAULT 'pending',
  idempotency_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pearl_coin_exchanges TO authenticated;
GRANT ALL ON public.pearl_coin_exchanges TO service_role;
ALTER TABLE public.pearl_coin_exchanges ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.pearl_coin_exchange_reversals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  original_exchange_id uuid NOT NULL UNIQUE REFERENCES public.pearl_coin_exchanges(id),
  reason text NOT NULL, reversed_by uuid NOT NULL, reversed_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.pearl_coin_exchange_reversals TO authenticated;
GRANT ALL ON public.pearl_coin_exchange_reversals TO service_role;
ALTER TABLE public.pearl_coin_exchange_reversals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.wallet_adjustment_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text UNIQUE NOT NULL DEFAULT ('YC-ADJ-' || to_char(now(),'YYYYMMDD') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  target_user_id uuid NOT NULL REFERENCES public.profiles(id),
  kind public.wallet_adjustment_kind NOT NULL,
  amount bigint NOT NULL CHECK (amount > 0),
  reason text NOT NULL,
  status public.wallet_adjustment_status NOT NULL DEFAULT 'pending',
  requires_dual_review boolean NOT NULL DEFAULT false,
  idempotency_key text UNIQUE, created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  applied_at timestamptz, reversed_at timestamptz,
  balance_before bigint, balance_after bigint
);
GRANT SELECT, INSERT, UPDATE ON public.wallet_adjustment_requests TO authenticated;
GRANT ALL ON public.wallet_adjustment_requests TO service_role;
ALTER TABLE public.wallet_adjustment_requests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.wallet_adjustment_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.wallet_adjustment_requests(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approved','rejected')),
  note text, reviewed_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.wallet_adjustment_reviews TO authenticated;
GRANT ALL ON public.wallet_adjustment_reviews TO service_role;
ALTER TABLE public.wallet_adjustment_reviews ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_debts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES public.charging_customers(id) ON DELETE CASCADE,
  agent_user_id uuid NOT NULL REFERENCES public.profiles(id),
  agency_id uuid REFERENCES public.charging_agencies(id),
  amount numeric(14,4) NOT NULL, currency text NOT NULL DEFAULT 'USD',
  reason text, status text NOT NULL DEFAULT 'open',
  due_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), settled_at timestamptz
);
GRANT SELECT, INSERT, UPDATE ON public.charging_debts TO authenticated;
GRANT ALL ON public.charging_debts TO service_role;
ALTER TABLE public.charging_debts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_debt_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_id uuid NOT NULL REFERENCES public.charging_debts(id) ON DELETE CASCADE,
  amount numeric(14,4) NOT NULL,
  method_code text, reference text,
  paid_at timestamptz NOT NULL DEFAULT now(), recorded_by uuid
);
GRANT SELECT, INSERT ON public.charging_debt_payments TO authenticated;
GRANT ALL ON public.charging_debt_payments TO service_role;
ALTER TABLE public.charging_debt_payments ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type text NOT NULL, title text NOT NULL, body text,
  entity_type text, entity_id text,
  read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cnot_user ON public.charging_notifications(user_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE ON public.charging_notifications TO authenticated;
GRANT ALL ON public.charging_notifications TO service_role;
ALTER TABLE public.charging_notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_agent_daily_stats (
  agent_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL,
  coins_sent bigint DEFAULT 0, coins_received bigint DEFAULT 0,
  pearls_sent bigint DEFAULT 0, pearls_received bigint DEFAULT 0,
  pearls_bought bigint DEFAULT 0, pearls_exchanged bigint DEFAULT 0,
  transfer_count int DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (agent_user_id, day)
);
GRANT SELECT, INSERT, UPDATE ON public.charging_agent_daily_stats TO authenticated;
GRANT ALL ON public.charging_agent_daily_stats TO service_role;
ALTER TABLE public.charging_agent_daily_stats ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.charging_agency_daily_stats (
  agency_id uuid NOT NULL REFERENCES public.charging_agencies(id) ON DELETE CASCADE,
  day date NOT NULL,
  coins_sent bigint DEFAULT 0, pearls_sent bigint DEFAULT 0,
  pearls_bought bigint DEFAULT 0, pearls_exchanged bigint DEFAULT 0,
  transfer_count int DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (agency_id, day)
);
GRANT SELECT, INSERT, UPDATE ON public.charging_agency_daily_stats TO authenticated;
GRANT ALL ON public.charging_agency_daily_stats TO service_role;
ALTER TABLE public.charging_agency_daily_stats ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.message_transaction_metadata (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid, txn_type text NOT NULL, txn_reference text NOT NULL,
  from_user_id uuid, to_user_id uuid, amount bigint, currency_code text,
  status text NOT NULL DEFAULT 'completed',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mtm_ref ON public.message_transaction_metadata(txn_reference);
CREATE INDEX IF NOT EXISTS idx_mtm_from ON public.message_transaction_metadata(from_user_id);
CREATE INDEX IF NOT EXISTS idx_mtm_to ON public.message_transaction_metadata(to_user_id);
GRANT SELECT, INSERT, UPDATE ON public.message_transaction_metadata TO authenticated;
GRANT ALL ON public.message_transaction_metadata TO service_role;
ALTER TABLE public.message_transaction_metadata ENABLE ROW LEVEL SECURITY;

-- Permissions
INSERT INTO public.permissions(key, module, label_ar, label_en) VALUES
  ('charging_agencies.read','charging','قراءة وكالات الشحن','Read charging agencies'),
  ('charging_agencies.create','charging','إنشاء وكالة شحن','Create charging agency'),
  ('charging_agencies.update','charging','تعديل وكالة شحن','Update charging agency'),
  ('charging_agencies.suspend','charging','تعليق وكالة شحن','Suspend charging agency'),
  ('charging_agencies.close','charging','إغلاق وكالة شحن','Close charging agency'),
  ('charging_agents.read','charging','قراءة الوكلاء','Read charging agents'),
  ('charging_agents.activate','charging','تفعيل وكيل شحن','Activate charging agent'),
  ('charging_agents.suspend','charging','تعليق وكيل شحن','Suspend charging agent'),
  ('charging_agents.update_limits','charging','تحديث حدود الوكيل','Update agent limits'),
  ('charging_coin_transfers.read','charging','قراءة تحويلات الكوينز','Read coin transfers'),
  ('charging_coin_transfers.create','charging','إنشاء تحويل كوينز','Create coin transfer'),
  ('charging_coin_transfers.reverse','charging','عكس تحويل كوينز','Reverse coin transfer'),
  ('charging_pearl_transfers.read','charging','قراءة تحويلات اللؤلؤ','Read pearl transfers'),
  ('charging_pearl_transfers.create','charging','إنشاء تحويل لؤلؤ','Create pearl transfer'),
  ('charging_pearl_transfers.reverse','charging','عكس تحويل لؤلؤ','Reverse pearl transfer'),
  ('pearl_purchases.read','charging','قراءة عمليات شراء اللؤلؤ','Read pearl purchases'),
  ('pearl_purchases.create','charging','إنشاء طلب شراء لؤلؤ','Create pearl purchase'),
  ('pearl_purchases.approve','charging','اعتماد شراء لؤلؤ','Approve pearl purchase'),
  ('pearl_purchases.reverse','charging','عكس شراء لؤلؤ','Reverse pearl purchase'),
  ('pearl_exchanges.read','charging','قراءة عمليات التبديل','Read exchanges'),
  ('pearl_exchanges.create','charging','إنشاء تبديل','Create exchange'),
  ('pearl_exchanges.manage_rates','charging','إدارة أسعار التبديل','Manage exchange rates'),
  ('pearl_exchanges.reverse','charging','عكس تبديل','Reverse exchange'),
  ('wallets.coins.credit','charging','إضافة كوينز','Credit coins'),
  ('wallets.coins.debit','charging','خصم كوينز','Debit coins'),
  ('wallets.pearls.credit','charging','إضافة لؤلؤ','Credit pearls'),
  ('wallets.pearls.debit','charging','خصم لؤلؤ','Debit pearls'),
  ('wallets.adjustments.review','charging','مراجعة تعديلات الأرصدة','Review adjustments'),
  ('charging_customers.read','charging','قراءة العملاء','Read customers'),
  ('charging_customers.update','charging','تعديل عملاء','Update customers'),
  ('charging_debts.read','charging','قراءة الديون','Read debts'),
  ('charging_debts.manage','charging','إدارة الديون','Manage debts'),
  ('charging_pricing.read','charging','قراءة التسعير','Read pricing'),
  ('charging_pricing.manage','charging','إدارة التسعير','Manage pricing'),
  ('charging_payment_methods.read','charging','قراءة وسائل الدفع','Read payment methods'),
  ('charging_payment_methods.manage','charging','إدارة وسائل الدفع','Manage payment methods'),
  ('charging_reports.read','charging','قراءة التقارير','Read charging reports')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions(role, permission_key)
SELECT 'finance'::admin_role, key FROM public.permissions
WHERE key LIKE 'charging_%' OR key LIKE 'wallets.%' OR key LIKE 'pearl_%'
ON CONFLICT DO NOTHING;

-- Helper functions
CREATE OR REPLACE FUNCTION public.is_charging_agent(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM public.charging_agent_settings s WHERE s.user_id = _user_id AND s.status = 'active');
$$;
REVOKE EXECUTE ON FUNCTION public.is_charging_agent(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_charging_agent(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_charging_agency_owner(_user_id uuid, _agency_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM public.charging_agencies a WHERE a.id = _agency_id AND _user_id IN (a.owner_user_id, a.deputy_user_id));
$$;
REVOKE EXECUTE ON FUNCTION public.is_charging_agency_owner(uuid,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_charging_agency_owner(uuid,uuid) TO authenticated;

-- SELECT policies
CREATE POLICY ca_read ON public.charging_agencies FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_agencies.read') OR owner_user_id = auth.uid() OR deputy_user_id = auth.uid());
CREATE POLICY cam_read ON public.charging_agency_members FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_agents.read') OR user_id = auth.uid() OR public.is_charging_agency_owner(auth.uid(), agency_id));
CREATE POLICY cas_read ON public.charging_agent_settings FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_agents.read') OR user_id = auth.uid());
CREATE POLICY cct_read ON public.charging_coin_transfers FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_coin_transfers.read') OR agent_user_id = auth.uid() OR recipient_user_id = auth.uid());
CREATE POLICY cctr_read ON public.charging_coin_transfer_reversals FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_coin_transfers.read'));
CREATE POLICY cpt_read ON public.charging_pearl_transfers FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_pearl_transfers.read') OR from_user_id = auth.uid() OR to_user_id = auth.uid());
CREATE POLICY cptr_read ON public.charging_pearl_transfer_reversals FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_pearl_transfers.read'));
CREATE POLICY ccust_read ON public.charging_customers FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_customers.read') OR user_id = auth.uid() OR preferred_agent_id = auth.uid() OR public.is_charging_agency_owner(auth.uid(), agency_id));
CREATE POLICY cpr_read ON public.charging_price_rules FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_pricing.read') OR public.is_charging_agent(auth.uid()));
CREATE POLICY cpm_read ON public.charging_payment_methods FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_payment_methods.read') OR agent_user_id = auth.uid() OR public.is_charging_agency_owner(auth.uid(), agency_id));
CREATE POLICY ppr_read ON public.pearl_purchase_requests FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_purchases.read') OR agent_user_id = auth.uid() OR user_id = auth.uid());
CREATE POLICY ppp_read ON public.pearl_purchase_payments FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_purchases.read')
      OR EXISTS (SELECT 1 FROM public.pearl_purchase_requests r WHERE r.id = request_id AND (r.agent_user_id = auth.uid() OR r.user_id = auth.uid())));
CREATE POLICY pprv_read ON public.pearl_purchase_reversals FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_purchases.read'));
CREATE POLICY pcer_read ON public.pearl_coin_exchange_rates FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_exchanges.read') OR status='active' OR public.is_charging_agent(auth.uid()));
CREATE POLICY pce_read ON public.pearl_coin_exchanges FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_exchanges.read') OR agent_user_id = auth.uid());
CREATE POLICY pcerv_read ON public.pearl_coin_exchange_reversals FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'pearl_exchanges.read'));
CREATE POLICY war_read ON public.wallet_adjustment_requests FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'wallets.adjustments.review')
      OR public.has_permission(auth.uid(),'wallets.coins.credit')
      OR public.has_permission(auth.uid(),'wallets.pearls.credit')
      OR target_user_id = auth.uid() OR created_by = auth.uid());
CREATE POLICY warv_read ON public.wallet_adjustment_reviews FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'wallets.adjustments.review'));
CREATE POLICY cd_read ON public.charging_debts FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_debts.read') OR agent_user_id = auth.uid() OR public.is_charging_agency_owner(auth.uid(), agency_id));
CREATE POLICY cdp_read ON public.charging_debt_payments FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_debts.read')
      OR EXISTS (SELECT 1 FROM public.charging_debts d WHERE d.id = debt_id AND d.agent_user_id = auth.uid()));
CREATE POLICY cn_read ON public.charging_notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_permission(auth.uid(),'charging_reports.read'));
CREATE POLICY cads_read ON public.charging_agent_daily_stats FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_reports.read') OR agent_user_id = auth.uid());
CREATE POLICY cagds_read ON public.charging_agency_daily_stats FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(),'charging_reports.read') OR public.is_charging_agency_owner(auth.uid(), agency_id));
CREATE POLICY mtm_read ON public.message_transaction_metadata FOR SELECT TO authenticated
  USING (from_user_id = auth.uid() OR to_user_id = auth.uid() OR public.has_permission(auth.uid(),'charging_reports.read'));

-- Block direct writes (restrictive for INSERT/UPDATE/DELETE only, SELECT stays open)
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'charging_agencies','charging_agency_members','charging_agent_settings',
    'charging_coin_transfers','charging_coin_transfer_reversals',
    'charging_pearl_transfers','charging_pearl_transfer_reversals',
    'charging_customers','charging_price_rules','charging_payment_methods',
    'pearl_purchase_requests','pearl_purchase_payments','pearl_purchase_reversals',
    'pearl_coin_exchange_rates','pearl_coin_exchanges','pearl_coin_exchange_reversals',
    'wallet_adjustment_requests','wallet_adjustment_reviews',
    'charging_debts','charging_debt_payments','charging_notifications',
    'charging_agent_daily_stats','charging_agency_daily_stats','message_transaction_metadata'
  ])
  LOOP
    EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false)', t||'_no_ins', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false)', t||'_no_upd', t);
    EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (false)', t||'_no_del', t);
  END LOOP;
END $$;

-- updated_at triggers
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY['charging_agencies','charging_agent_settings','charging_customers','charging_price_rules'])
  LOOP
    EXECUTE format('CREATE TRIGGER trg_upd_%I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', t, t);
  END LOOP;
END $$;
