
-- =========================================================================
-- CHARGING AGENCIES SYSTEM — Phase A: Schema, Permissions, RLS
-- =========================================================================

-- 1) Extend ledger reasons for charging domain
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'game_win';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'game_loss';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'charging_coin_transfer';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'charging_coin_transfer_reverse';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'charging_pearl_transfer';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'charging_pearl_transfer_reverse';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'pearl_purchase';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'pearl_purchase_reverse';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'pearl_to_coin_exchange';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'pearl_to_coin_exchange_reverse';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'admin_coin_credit';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'admin_coin_debit';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'admin_pearl_credit';
ALTER TYPE public.ledger_reason ADD VALUE IF NOT EXISTS 'admin_pearl_debit';
