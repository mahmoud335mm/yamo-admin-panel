
-- ============================================================
-- PHASE 2 — Users + Wallet Ledger
-- ============================================================

CREATE TYPE public.user_status         AS ENUM ('active','banned','suspended','deleted');
CREATE TYPE public.verification_status AS ENUM ('unverified','pending','verified','rejected');
CREATE TYPE public.gender              AS ENUM ('male','female','other','unspecified');
CREATE TYPE public.ledger_direction    AS ENUM ('credit','debit');
CREATE TYPE public.ledger_reason       AS ENUM (
  'recharge','gift_sent','gift_received','call_cost','withdrawal',
  'refund','bonus','penalty','transfer_in','transfer_out','adjustment','reward'
);
CREATE TYPE public.wallet_account      AS ENUM ('coins','diamonds','bonus');

-- ---------- profiles ----------
CREATE TABLE public.profiles (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_uid         TEXT UNIQUE,
  username             TEXT UNIQUE,
  display_name         TEXT,
  phone                TEXT,
  country              TEXT,
  language             TEXT DEFAULT 'ar',
  gender               public.gender NOT NULL DEFAULT 'unspecified',
  birth_date           DATE,
  avatar_url           TEXT,
  bio                  TEXT,
  level                INTEGER NOT NULL DEFAULT 1,
  vip_level            INTEGER NOT NULL DEFAULT 0,
  status               public.user_status NOT NULL DEFAULT 'active',
  verification         public.verification_status NOT NULL DEFAULT 'unverified',
  agency_id            UUID,
  bd_id                UUID,
  last_seen_at         TIMESTAMPTZ,
  is_demo              BOOLEAN NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX profiles_status_idx    ON public.profiles(status);
CREATE INDEX profiles_username_trgm ON public.profiles(lower(username));
CREATE INDEX profiles_phone_idx     ON public.profiles(phone);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "read profiles" ON public.profiles FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'users.read'));
CREATE POLICY "write profiles" ON public.profiles FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(), 'users.write'))
  WITH CHECK (public.has_permission(auth.uid(), 'users.write'));
CREATE POLICY "insert profiles" ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(), 'users.write'));
CREATE POLICY "delete profiles" ON public.profiles FOR DELETE TO authenticated
  USING (public.has_permission(auth.uid(), 'users.write'));

CREATE TRIGGER profiles_touch BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------- devices ----------
CREATE TABLE public.user_devices (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_id    TEXT NOT NULL,
  platform     TEXT,
  os_version   TEXT,
  app_version  TEXT,
  push_token   TEXT,
  last_seen_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_devices TO authenticated;
GRANT ALL ON public.user_devices TO service_role;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read user_devices" ON public.user_devices FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'users.read'));
CREATE POLICY "write user_devices" ON public.user_devices FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(), 'users.write'))
  WITH CHECK (public.has_permission(auth.uid(), 'users.write'));

-- ---------- sessions ----------
CREATE TABLE public.user_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_id     TEXT,
  ip_address    TEXT,
  country       TEXT,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at      TIMESTAMPTZ
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_sessions TO authenticated;
GRANT ALL ON public.user_sessions TO service_role;
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read user_sessions" ON public.user_sessions FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'users.read'));

-- ---------- wallets ----------
CREATE TABLE public.wallets (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  account      public.wallet_account NOT NULL,
  balance      BIGINT NOT NULL DEFAULT 0,
  reserved     BIGINT NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, account)
);
CREATE INDEX wallets_user_idx ON public.wallets(user_id);
GRANT SELECT, INSERT, UPDATE ON public.wallets TO authenticated;
GRANT ALL ON public.wallets TO service_role;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read wallets" ON public.wallets FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'economy.read'));
CREATE POLICY "write wallets" ON public.wallets FOR UPDATE TO authenticated
  USING (public.has_permission(auth.uid(), 'economy.write'))
  WITH CHECK (public.has_permission(auth.uid(), 'economy.write'));

CREATE TRIGGER wallets_touch BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------- ledger (append-only) ----------
CREATE TABLE public.wallet_ledger (
  id             BIGSERIAL PRIMARY KEY,
  wallet_id      UUID NOT NULL REFERENCES public.wallets(id) ON DELETE RESTRICT,
  user_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  account        public.wallet_account NOT NULL,
  direction      public.ledger_direction NOT NULL,
  reason         public.ledger_reason NOT NULL,
  amount         BIGINT NOT NULL CHECK (amount > 0),
  balance_after  BIGINT NOT NULL,
  reference      TEXT,
  metadata       JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by     UUID REFERENCES public.admin_users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ledger_user_idx    ON public.wallet_ledger(user_id, created_at DESC);
CREATE INDEX ledger_wallet_idx  ON public.wallet_ledger(wallet_id, created_at DESC);
CREATE INDEX ledger_reason_idx  ON public.wallet_ledger(reason);
GRANT SELECT, INSERT ON public.wallet_ledger TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.wallet_ledger_id_seq TO authenticated;
GRANT ALL ON public.wallet_ledger TO service_role;
GRANT ALL ON SEQUENCE public.wallet_ledger_id_seq TO service_role;
ALTER TABLE public.wallet_ledger ENABLE ROW LEVEL SECURITY;

-- append-only: block UPDATE/DELETE by not creating those policies
CREATE POLICY "read ledger" ON public.wallet_ledger FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'economy.read'));
CREATE POLICY "insert ledger" ON public.wallet_ledger FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(auth.uid(), 'economy.write'));

-- ---------- transactions ----------
CREATE TABLE public.transactions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  type         TEXT NOT NULL,           -- recharge/withdrawal/gift/refund/...
  status       TEXT NOT NULL DEFAULT 'pending',
  amount       BIGINT NOT NULL,
  currency     TEXT NOT NULL DEFAULT 'coins',
  provider     TEXT,
  provider_ref TEXT,
  metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX transactions_user_idx   ON public.transactions(user_id, created_at DESC);
CREATE INDEX transactions_status_idx ON public.transactions(status);
GRANT SELECT, INSERT, UPDATE ON public.transactions TO authenticated;
GRANT ALL ON public.transactions TO service_role;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read transactions" ON public.transactions FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'economy.read'));
CREATE POLICY "write transactions" ON public.transactions FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(), 'economy.write'))
  WITH CHECK (public.has_permission(auth.uid(), 'economy.write'));

CREATE TRIGGER transactions_touch BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------- penalties ----------
CREATE TABLE public.user_penalties (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,   -- warning/ban/mute
  reason      TEXT NOT NULL,
  duration_h  INTEGER,
  starts_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at     TIMESTAMPTZ,
  issued_by   UUID REFERENCES public.admin_users(id),
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.user_penalties TO authenticated;
GRANT ALL ON public.user_penalties TO service_role;
ALTER TABLE public.user_penalties ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read penalties" ON public.user_penalties FOR SELECT TO authenticated
  USING (public.has_permission(auth.uid(), 'users.read'));
CREATE POLICY "write penalties" ON public.user_penalties FOR ALL TO authenticated
  USING (public.has_permission(auth.uid(), 'users.ban'))
  WITH CHECK (public.has_permission(auth.uid(), 'users.ban'));

-- ============================================================
-- DEMO SEED (is_demo=true → easy to delete via WHERE is_demo)
-- ============================================================
INSERT INTO public.profiles (external_uid, username, display_name, phone, country, gender, level, vip_level, status, verification, is_demo) VALUES
  ('U100001','ali_star','علي النجم','+9647701234567','IQ','male',12,2,'active','verified',true),
  ('U100002','sara_queen','سارة الملكة','+9647702345678','IQ','female',18,3,'active','verified',true),
  ('U100003','omar_pro','عمر برو','+201001234567','EG','male',8,1,'active','pending',true),
  ('U100004','lina_moon','لينا القمر','+201002345678','EG','female',22,4,'active','verified',true),
  ('U100005','yousef_x','يوسف اكس','+966501234567','SA','male',5,0,'suspended','unverified',true),
  ('U100006','maya_pearl','مايا اللؤلؤة','+966502345678','SA','female',14,2,'banned','verified',true);

INSERT INTO public.wallets (user_id, account, balance)
SELECT id, 'coins'::public.wallet_account, (random()*50000)::bigint FROM public.profiles WHERE is_demo;
INSERT INTO public.wallets (user_id, account, balance)
SELECT id, 'diamonds'::public.wallet_account, (random()*5000)::bigint FROM public.profiles WHERE is_demo;

INSERT INTO public.wallet_ledger (wallet_id, user_id, account, direction, reason, amount, balance_after, reference)
SELECT w.id, w.user_id, w.account, 'credit'::public.ledger_direction, 'recharge'::public.ledger_reason,
       w.balance, w.balance, 'seed:recharge'
FROM public.wallets w JOIN public.profiles p ON p.id = w.user_id WHERE p.is_demo AND w.account='coins';

INSERT INTO public.transactions (user_id, type, status, amount, currency, provider, provider_ref, metadata)
SELECT id, 'recharge', 'succeeded', 5000, 'coins', 'stripe', 'demo-'||external_uid, jsonb_build_object('seed',true)
FROM public.profiles WHERE is_demo;
