-- Phase 0, migration 1: extensions, shared enums and the small helpers every
-- later table uses. Domain rules live in docs/PROPOSAL.md section 8 and CLAUDE.md.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

-- Roles a login can hold. Barangay-level roles are scoped to one barangay.
-- LGU-level roles (accountant, bookkeeper, admin, COA auditor) cover every
-- barangay of the city/municipality. COA auditors are read-only everywhere.
create type app_role as enum (
  'punong_barangay',
  'barangay_treasurer',
  'cca',                   -- Chairman, Committee on Appropriations
  'barangay_secretary',
  'sk_chairperson',
  'deputized_collector',
  'property_custodian',
  'petty_cash_custodian',
  'lgu_accountant',        -- City/Municipal Accountant
  'lgu_bookkeeper',
  'lgu_admin',
  'coa_auditor'
);

create type lgu_type as enum ('city', 'municipality');

-- Manual Chapter II: funds the barangay must keep apart. One STF per purpose.
create type fund_type as enum (
  'general',       -- General Fund
  'sk',            -- 10% Sangguniang Kabataan
  'ldrrmf',        -- 5% Local Disaster Risk Reduction and Management Fund
  'development',   -- 20% Development Fund
  'continuing',    -- continuing appropriations
  'stf'            -- Special Trust Fund
);

create type account_class as enum ('Asset', 'Liability', 'Equity', 'Revenue', 'Expense');
create type normal_balance as enum ('Dr', 'Cr');

create type accountable_form_type as enum ('official_receipt', 'cash_ticket', 'check');
create type accountable_form_status as enum ('on_hand', 'in_use', 'used_up', 'returned', 'lost');

create type journal_book as enum ('JCT', 'GJ');   -- Journal of Cash Transactions / General Journal
create type entry_status as enum ('draft', 'posted', 'reversed');
create type period_status as enum ('open', 'closed');

-- Keeps updated_at honest on every table that has one.
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Asia/Manila is the only calendar that matters to COA deadlines.
create or replace function manila_today() returns date
language sql stable as $$
  select (now() at time zone 'Asia/Manila')::date
$$;
