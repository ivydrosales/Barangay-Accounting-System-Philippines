-- Phase 1, migration 5: collections (manual Chapter IV; Annexes 8, 9 and 9.1).
--
--   Official Receipt (Accountable Form 51) -> issued in strict serial order
--   from a booklet held in accountable_form (4.1.3). Cancelled ORs stay.
--   RCR (Annex 9.1) -> a Deputized Barangay Collector's daily report, which
--   the Barangay Treasurer acknowledges when the cash is turned over (4.2.3).
--   RCD (Annex 9) -> the BT's daily report: own ORs + acknowledged RCRs +
--   deposits. The BT certifies it; the C/M Accountant posts it to the JCT
--   with the pro-forma entries in 4.3.1 and 4.3.2.
--   Cashbook (Annex 8) -> a query over certified RCDs (more sources join in
--   later phases: bank memos, checks, cash advances, petty cash).

-- ---------------------------------------------------------------------------
-- Document numbers follow the manual's layout 0000-00-000 (Annex 9 A.4):
-- year, month, three-digit serial, one series per year.
-- ---------------------------------------------------------------------------

create or replace function next_document_number(
  p_barangay uuid, p_doc_type text, p_date date, p_monthly boolean default false
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_lgu    uuid;
  v_year   int := extract(year from p_date)::int;
  v_month  int := extract(month from p_date)::int;
  v_serial int;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'unknown barangay %', p_barangay;
  end if;

  insert into document_sequence (lgu_id, barangay_id, doc_type, fiscal_year, month, last_serial)
  values (v_lgu, p_barangay, p_doc_type, v_year, case when p_monthly then v_month else 0 end, 1)
  on conflict (barangay_id, doc_type, fiscal_year, month)
    do update set last_serial = document_sequence.last_serial + 1
  returning last_serial into v_serial;

  return format('%s-%s-%s', v_year, lpad(v_month::text, 2, '0'), lpad(v_serial::text, 3, '0'));
end $$;

-- New tables created from here on get the same grants as the Phase 0 ones.
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated, service_role;
alter default privileges in schema public grant usage, select on sequences to authenticated, service_role;
alter default privileges in schema public grant execute on functions to authenticated, service_role;

create type payment_mode as enum ('cash', 'check');
create type or_status as enum ('issued', 'cancelled');
create type rcr_status as enum ('draft', 'certified', 'acknowledged');
create type rcd_status as enum ('draft', 'certified', 'posted');

-- ---------------------------------------------------------------------------
-- Nature of collections -> the account credited. LGU-wide; the Accountant's
-- office maintains the list. Defaults are created with every LGU.
-- ---------------------------------------------------------------------------

create table collection_type (
  id           uuid primary key default gen_random_uuid(),
  lgu_id       uuid not null references lgu(id),
  name         text not null,                          -- as written on the face of the OR
  account_code text not null references account(code),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (lgu_id, name)
);

create or replace function collection_type_guard() returns trigger
language plpgsql as $$
declare v_class account_class;
begin
  select class into v_class from account where code = new.account_code and is_active;
  if v_class is null or v_class not in ('Revenue', 'Liability', 'Asset') then
    raise exception 'collections are credited to an income, liability or asset account (4.3.1); % is not one', new.account_code
      using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger collection_type_guard before insert or update on collection_type
  for each row execute function collection_type_guard();

create or replace function seed_collection_types() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into collection_type (lgu_id, name, account_code) values
    (new.id, 'Real Property Tax',                 '4-01-01-010'),
    (new.id, 'Business Tax',                      '4-01-02-010'),
    (new.id, 'Other Taxes',                       '4-01-04-990'),
    (new.id, 'Fines and Penalties',               '4-01-05-990'),
    (new.id, 'Clearance and Certification Fees',  '4-04-01-010'),
    (new.id, 'Other Service Revenue',             '4-04-01-990'),
    (new.id, 'Garbage Fees',                      '4-04-02-010'),
    (new.id, 'Market Fees',                       '4-04-02-020'),
    (new.id, 'Other Business Income',             '4-04-02-990'),
    (new.id, 'Grants and Donations in Cash',      '4-03-02-010'),
    (new.id, 'Trust Receipts',                    '2-03-01-010'),
    (new.id, 'Guaranty/Security Deposits',        '2-03-01-020'),
    (new.id, 'Refund of Cash Advance',            '1-03-03-020'),
    (new.id, 'Refund of Payroll Advance',         '1-03-03-010');
  return new;
end $$;

create trigger lgu_seed_collection_types
  after insert on lgu
  for each row execute function seed_collection_types();

-- ---------------------------------------------------------------------------
-- Reports (created before the OR so the OR can point at them)
-- ---------------------------------------------------------------------------

create table rcd (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  rcd_no                text,                                  -- assigned when certified
  rcd_date              date not null,
  treasurer_official_id uuid references official(id),
  status                rcd_status not null default 'draft',
  certified_at          timestamptz,
  certified_by          uuid,
  posted_at             timestamptz,
  posted_by             uuid,
  remarks               text,
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, rcd_no),
  constraint rcd_numbered_when_certified check ((status = 'draft') = (rcd_no is null))
);

create index on rcd (barangay_id, rcd_date);

create table rcr (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  rcr_no                text,                                  -- assigned when certified
  rcr_date              date not null,
  collector_official_id uuid not null references official(id),
  beginning_balance     numeric(14,2) not null default 0 check (beginning_balance >= 0),
  status                rcr_status not null default 'draft',
  certified_at          timestamptz,
  acknowledged_at       timestamptz,
  acknowledged_by       uuid,
  rcd_id                uuid references rcd(id) on delete set null,
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, rcr_no),
  constraint rcr_numbered_when_certified check ((status = 'draft') = (rcr_no is null))
);

create index on rcr (barangay_id, rcr_date);

-- ---------------------------------------------------------------------------
-- Official Receipts
-- ---------------------------------------------------------------------------

create table official_receipt (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  accountable_form_id   uuid not null references accountable_form(id),   -- the booklet
  serial_no             bigint not null,
  or_date               date not null,
  payor                 text not null,
  collection_type_id    uuid not null references collection_type(id),
  nature                text not null,                     -- as written on the OR
  particulars           text,
  fund_id               uuid not null references fund(id),
  amount                numeric(14,2) not null check (amount > 0),
  payment_mode          payment_mode not null default 'cash',
  check_bank            text,
  check_no              text,
  check_date            date,
  collector_official_id uuid references official(id),     -- BT or the DBC who issued it
  status                or_status not null default 'issued',
  cancelled_reason      text,
  cancelled_at          timestamptz,
  cancelled_by          uuid,
  rcr_id                uuid references rcr(id) on delete set null,   -- DBC ORs are reported on an RCR
  rcd_id                uuid references rcd(id) on delete set null,   -- BT ORs go straight on the RCD
  issued_by             uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  foreign key (fund_id, barangay_id) references fund(id, barangay_id),
  unique (accountable_form_id, serial_no),
  constraint check_details check (payment_mode = 'cash' or (check_bank is not null and check_no is not null)),
  constraint reported_once check (rcr_id is null or rcd_id is null)
);

create index on official_receipt (barangay_id, or_date);
create index on official_receipt (rcd_id);
create index on official_receipt (rcr_id);

-- ---------------------------------------------------------------------------
-- Deposits with the depository bank (validated deposit slip)
-- ---------------------------------------------------------------------------

create table deposit (
  id              uuid primary key default gen_random_uuid(),
  lgu_id          uuid not null references lgu(id),
  barangay_id     uuid not null references barangay(id),
  bank_account_id uuid not null references bank_account(id),
  fund_id         uuid not null references fund(id),
  deposit_date    date not null,
  reference       text not null,                           -- validated deposit slip number
  amount          numeric(14,2) not null check (amount > 0),
  rcd_id          uuid references rcd(id) on delete set null,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  foreign key (fund_id, barangay_id) references fund(id, barangay_id)
);

create index on deposit (barangay_id, deposit_date);
create index on deposit (rcd_id);

do $$
declare t text;
begin
  foreach t in array array['collection_type', 'rcd', 'rcr', 'official_receipt', 'deposit']
  loop
    execute format('create trigger %I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
    execute format('create trigger %I_audit after insert or update or delete on %I for each row execute function write_audit_log()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Guards: a report that has been certified is frozen, and so is everything on it.
-- ---------------------------------------------------------------------------

create or replace function rcd_is_frozen(p_rcd uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rcd where id = p_rcd and status <> 'draft')
$$;

create or replace function rcr_is_frozen(p_rcr uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rcr where id = p_rcr and status <> 'draft')
$$;

create or replace function official_receipt_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Official Receipts are never deleted; cancel OR % instead (4.1.3)', old.serial_no using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    if current_setting('app.issuing_or', true) is distinct from new.accountable_form_id::text then
      raise exception 'use issue_official_receipt() so serial numbers stay in sequence' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if (new.serial_no, new.accountable_form_id, new.barangay_id, new.lgu_id)
     is distinct from (old.serial_no, old.accountable_form_id, old.barangay_id, old.lgu_id) then
    raise exception 'OR % keeps its serial number and booklet', old.serial_no using errcode = 'P0001';
  end if;
  if old.status = 'cancelled' and new.status = 'issued' then
    raise exception 'cancelled OR % stays cancelled', old.serial_no using errcode = 'P0001';
  end if;
  if old.rcd_id is not null and rcd_is_frozen(old.rcd_id) then
    raise exception 'OR % is on a certified RCD and cannot change', old.serial_no using errcode = 'P0001';
  end if;
  if old.rcr_id is not null and rcr_is_frozen(old.rcr_id) then
    raise exception 'OR % is on a certified RCR and cannot change', old.serial_no using errcode = 'P0001';
  end if;
  if new.rcd_id is distinct from old.rcd_id and new.rcd_id is not null and rcd_is_frozen(new.rcd_id) then
    raise exception 'cannot add OR % to a certified RCD', old.serial_no using errcode = 'P0001';
  end if;
  if new.rcr_id is distinct from old.rcr_id and new.rcr_id is not null and rcr_is_frozen(new.rcr_id) then
    raise exception 'cannot add OR % to a certified RCR', old.serial_no using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger official_receipt_guard before insert or update or delete on official_receipt
  for each row execute function official_receipt_guard();

create or replace function deposit_guard() returns trigger
language plpgsql as $$
begin
  if old.rcd_id is not null and rcd_is_frozen(old.rcd_id) then
    raise exception 'deposit % is on a certified RCD and cannot change', old.reference using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and new.rcd_id is distinct from old.rcd_id and new.rcd_id is not null and rcd_is_frozen(new.rcd_id) then
    raise exception 'cannot add a deposit to a certified RCD' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end $$;

create trigger deposit_guard before update or delete on deposit
  for each row execute function deposit_guard();

create or replace function rcr_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'RCR % is certified and cannot be deleted', old.rcr_no using errcode = 'P0001';
    end if;
    return old;
  end if;

  if new.status = 'certified' and old.status = 'draft'
     and current_setting('app.certifying_rcr', true) is distinct from old.id::text then
    raise exception 'use certify_rcr() to certify' using errcode = 'P0001';
  end if;

  if old.status = 'draft' then
    return new;
  end if;

  -- certified or acknowledged: only the acknowledgement and the link to the RCD may change
  if old.status = 'certified' and new.status = 'acknowledged'
     and current_setting('app.acknowledging_rcr', true) = old.id::text then
    return new;
  end if;
  if to_jsonb(new) - 'rcd_id' - 'updated_at' = to_jsonb(old) - 'rcd_id' - 'updated_at' then
    if new.rcd_id is not null and rcd_is_frozen(new.rcd_id) then
      raise exception 'cannot add RCR % to a certified RCD', old.rcr_no using errcode = 'P0001';
    end if;
    if old.rcd_id is not null and rcd_is_frozen(old.rcd_id) then
      raise exception 'RCR % is on a certified RCD', old.rcr_no using errcode = 'P0001';
    end if;
    return new;
  end if;
  raise exception 'RCR % is certified and cannot change', old.rcr_no using errcode = 'P0001';
end $$;

create trigger rcr_guard before update or delete on rcr
  for each row execute function rcr_guard();

create or replace function rcd_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'RCD % is certified and cannot be deleted', old.rcd_no using errcode = 'P0001';
    end if;
    return old;
  end if;

  if new.status = 'certified' and old.status = 'draft'
     and current_setting('app.certifying_rcd', true) is distinct from old.id::text then
    raise exception 'use certify_rcd() to certify' using errcode = 'P0001';
  end if;
  if old.status = 'draft' then
    return new;
  end if;
  if old.status = 'certified' and new.status = 'posted'
     and current_setting('app.posting_rcd', true) = old.id::text
     and to_jsonb(new) - 'status' - 'posted_at' - 'posted_by' - 'updated_at'
         = to_jsonb(old) - 'status' - 'posted_at' - 'posted_by' - 'updated_at' then
    return new;
  end if;
  raise exception 'RCD % is certified and cannot change', old.rcd_no using errcode = 'P0001';
end $$;

create trigger rcd_guard before update or delete on rcd
  for each row execute function rcd_guard();

-- ---------------------------------------------------------------------------
-- Issuing and cancelling Official Receipts
-- ---------------------------------------------------------------------------

create or replace function issue_official_receipt(
  p_form            uuid,
  p_date            date,
  p_payor           text,
  p_collection_type uuid,
  p_fund            uuid,
  p_amount          numeric,
  p_mode            payment_mode default 'cash',
  p_check_bank      text default null,
  p_check_no        text default null,
  p_check_date      date default null,
  p_particulars     text default null,
  p_collector       uuid default null
) returns official_receipt
language plpgsql as $$
declare
  v_form accountable_form;
  v_type collection_type;
  v_or   official_receipt;
begin
  select * into v_form from accountable_form where id = p_form for update;
  if v_form.id is null then
    raise exception 'booklet not found or not accessible';
  end if;
  if v_form.form_type <> 'official_receipt' then
    raise exception 'booklet % is not an Official Receipt booklet', v_form.series;
  end if;
  if v_form.status not in ('on_hand', 'in_use') or v_form.next_serial > v_form.serial_to then
    raise exception 'booklet % (%-%) is %', v_form.series, v_form.serial_from, v_form.serial_to,
      case when v_form.next_serial > v_form.serial_to then 'used up' else v_form.status::text end;
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'the amount must be more than zero';
  end if;
  if coalesce(trim(p_payor), '') = '' then
    raise exception 'the payor is required (4.1.4: all particulars filled out)';
  end if;
  if p_mode = 'check' and (p_check_bank is null or p_check_no is null) then
    raise exception 'check payments need the bank and check number (4.1.10)';
  end if;
  if is_period_closed(v_form.barangay_id, p_date) then
    raise exception 'period is closed for %', p_date;
  end if;
  if exists (select 1 from official_receipt where accountable_form_id = v_form.id and or_date > p_date) then
    raise exception 'OR dates must follow the serial order: a later OR of booklet % is already dated after %', v_form.series, p_date;
  end if;

  select * into v_type from collection_type
  where id = p_collection_type and lgu_id = v_form.lgu_id and is_active;
  if v_type.id is null then
    raise exception 'unknown nature of collection';
  end if;

  perform set_config('app.issuing_or', v_form.id::text, true);
  insert into official_receipt (
    lgu_id, barangay_id, accountable_form_id, serial_no, or_date, payor,
    collection_type_id, nature, particulars, fund_id, amount,
    payment_mode, check_bank, check_no, check_date, collector_official_id)
  values (
    v_form.lgu_id, v_form.barangay_id, v_form.id, v_form.next_serial, p_date, trim(p_payor),
    v_type.id, v_type.name, p_particulars, p_fund, p_amount,
    p_mode, p_check_bank, p_check_no, p_check_date, coalesce(p_collector, v_form.issued_to_official_id))
  returning * into v_or;
  perform set_config('app.issuing_or', '', true);

  update accountable_form
  set next_serial = next_serial + 1,
      status      = case when next_serial + 1 > serial_to then 'used_up'::accountable_form_status else 'in_use' end
  where id = v_form.id;

  return v_or;
end $$;

create or replace function cancel_official_receipt(p_or uuid, p_reason text) returns official_receipt
language plpgsql as $$
declare v_or official_receipt;
begin
  select * into v_or from official_receipt where id = p_or for update;
  if v_or.id is null then
    raise exception 'OR not found or not accessible';
  end if;
  if v_or.status = 'cancelled' then
    return v_or;
  end if;
  if (v_or.rcd_id is not null and rcd_is_frozen(v_or.rcd_id)) or (v_or.rcr_id is not null and rcr_is_frozen(v_or.rcr_id)) then
    raise exception 'OR % was already reported; record a refund or a dishonored check instead', v_or.serial_no;
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required to cancel an OR';
  end if;

  update official_receipt
  set status = 'cancelled', cancelled_reason = trim(p_reason), cancelled_at = now(), cancelled_by = auth.uid()
  where id = p_or
  returning * into v_or;
  return v_or;
end $$;

-- ---------------------------------------------------------------------------
-- RCR: the collector's report (Annex 9.1)
-- ---------------------------------------------------------------------------

-- Creates a draft RCR for the collector covering every OR of theirs not yet
-- reported, dated on or before p_date.
create or replace function prepare_rcr(p_barangay uuid, p_date date, p_collector uuid) returns rcr
language plpgsql as $$
declare
  v_lgu uuid;
  v_rcr rcr;
  v_n   int;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'barangay not found or not accessible';
  end if;
  if not exists (select 1 from official where id = p_collector and barangay_id = p_barangay and is_active) then
    raise exception 'collector is not an active official of this barangay';
  end if;
  if exists (select 1 from official where id = p_collector and position = 'Barangay Treasurer') then
    raise exception 'the Barangay Treasurer reports collections on the RCD, not on an RCR (4.2.1)';
  end if;
  if exists (select 1 from rcr where barangay_id = p_barangay and collector_official_id = p_collector and status = 'draft') then
    raise exception 'this collector already has a draft RCR; certify or delete it first';
  end if;

  insert into rcr (lgu_id, barangay_id, rcr_date, collector_official_id)
  values (v_lgu, p_barangay, p_date, p_collector)
  returning * into v_rcr;

  update official_receipt
  set rcr_id = v_rcr.id
  where barangay_id = p_barangay and collector_official_id = p_collector
    and rcr_id is null and rcd_id is null and or_date <= p_date;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'nothing to report: no unreported ORs for this collector up to %', p_date;
  end if;
  return v_rcr;
end $$;

create or replace function certify_rcr(p_rcr uuid) returns rcr
language plpgsql as $$
declare v_rcr rcr;
begin
  select * into v_rcr from rcr where id = p_rcr for update;
  if v_rcr.id is null then
    raise exception 'RCR not found or not accessible';
  end if;
  if v_rcr.status <> 'draft' then
    return v_rcr;
  end if;
  if not exists (select 1 from official_receipt where rcr_id = p_rcr) then
    raise exception 'an RCR needs at least one OR';
  end if;
  if is_period_closed(v_rcr.barangay_id, v_rcr.rcr_date) then
    raise exception 'period is closed for %', v_rcr.rcr_date;
  end if;

  perform set_config('app.certifying_rcr', p_rcr::text, true);
  update rcr
  set status = 'certified', certified_at = now(),
      rcr_no = next_document_number(v_rcr.barangay_id, 'RCR', v_rcr.rcr_date)
  where id = p_rcr
  returning * into v_rcr;
  perform set_config('app.certifying_rcr', '', true);
  return v_rcr;
end $$;

-- The BT signs the acknowledgement when the collector turns over the cash.
create or replace function acknowledge_rcr(p_rcr uuid) returns rcr
language plpgsql as $$
declare v_rcr rcr;
begin
  select * into v_rcr from rcr where id = p_rcr for update;
  if v_rcr.id is null then
    raise exception 'RCR not found or not accessible';
  end if;
  if v_rcr.status = 'draft' then
    raise exception 'the collector must certify RCR before the Treasurer acknowledges it';
  end if;
  if v_rcr.status = 'acknowledged' then
    return v_rcr;
  end if;

  perform set_config('app.acknowledging_rcr', p_rcr::text, true);
  update rcr set status = 'acknowledged', acknowledged_at = now(), acknowledged_by = auth.uid()
  where id = p_rcr
  returning * into v_rcr;
  perform set_config('app.acknowledging_rcr', '', true);
  return v_rcr;
end $$;

-- ---------------------------------------------------------------------------
-- RCD: the Treasurer's report (Annex 9)
-- ---------------------------------------------------------------------------

create or replace function prepare_rcd(p_barangay uuid, p_date date) returns rcd
language plpgsql as $$
declare
  v_lgu uuid;
  v_rcd rcd;
  v_ors int; v_rcrs int; v_deps int;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'barangay not found or not accessible';
  end if;
  if exists (select 1 from rcd where barangay_id = p_barangay and status = 'draft') then
    raise exception 'there is already a draft RCD; certify or delete it first';
  end if;
  if is_period_closed(p_barangay, p_date) then
    raise exception 'period is closed for %', p_date;
  end if;

  insert into rcd (lgu_id, barangay_id, rcd_date, treasurer_official_id)
  values (v_lgu, p_barangay, p_date,
          (select id from official
           where barangay_id = p_barangay and is_active and position = 'Barangay Treasurer'
           order by term_start desc nulls last limit 1))
  returning * into v_rcd;

  -- the BT's own ORs (cancelled ones included, as the annex requires);
  -- collectors' ORs reach the RCD only through an acknowledged RCR
  update official_receipt o set rcd_id = v_rcd.id
  where o.barangay_id = p_barangay and o.rcd_id is null and o.rcr_id is null and o.or_date <= p_date
    and (o.collector_official_id is null
         or exists (select 1 from official f where f.id = o.collector_official_id and f.position = 'Barangay Treasurer'));
  get diagnostics v_ors = row_count;

  -- collectors' reports whose cash the BT has acknowledged
  update rcr set rcd_id = v_rcd.id
  where barangay_id = p_barangay and rcd_id is null and status = 'acknowledged' and rcr_date <= p_date;
  get diagnostics v_rcrs = row_count;

  update deposit set rcd_id = v_rcd.id
  where barangay_id = p_barangay and rcd_id is null and deposit_date <= p_date;
  get diagnostics v_deps = row_count;

  if v_ors + v_rcrs + v_deps = 0 then
    raise exception 'nothing to report up to %: no unreported ORs, acknowledged RCRs or deposits', p_date;
  end if;
  return v_rcd;
end $$;

create or replace function certify_rcd(p_rcd uuid) returns rcd
language plpgsql as $$
declare v_rcd rcd;
begin
  select * into v_rcd from rcd where id = p_rcd for update;
  if v_rcd.id is null then
    raise exception 'RCD not found or not accessible';
  end if;
  if v_rcd.status <> 'draft' then
    return v_rcd;
  end if;
  if is_period_closed(v_rcd.barangay_id, v_rcd.rcd_date) then
    raise exception 'period is closed for %', v_rcd.rcd_date;
  end if;
  if not exists (select 1 from official_receipt where rcd_id = p_rcd)
     and not exists (select 1 from rcr where rcd_id = p_rcd)
     and not exists (select 1 from deposit where rcd_id = p_rcd) then
    raise exception 'an empty RCD cannot be certified';
  end if;

  perform set_config('app.certifying_rcd', p_rcd::text, true);
  update rcd
  set status = 'certified', certified_at = now(), certified_by = auth.uid(),
      rcd_no = next_document_number(v_rcd.barangay_id, 'RCD', v_rcd.rcd_date)
  where id = p_rcd
  returning * into v_rcd;
  perform set_config('app.certifying_rcd', '', true);
  return v_rcd;
end $$;

-- ---------------------------------------------------------------------------
-- Totals
-- ---------------------------------------------------------------------------

create or replace view rcr_totals as
select r.id as rcr_id,
       coalesce(sum(o.amount) filter (where o.status = 'issued'), 0)                              as total,
       coalesce(sum(o.amount) filter (where o.status = 'issued' and o.payment_mode = 'cash'), 0)  as cash,
       coalesce(sum(o.amount) filter (where o.status = 'issued' and o.payment_mode = 'check'), 0) as checks,
       count(o.id)                                                                                as or_count
from rcr r
left join official_receipt o on o.rcr_id = r.id
group by r.id;

create or replace view rcd_totals as
select d.id as rcd_id,
       coalesce((select sum(amount) from official_receipt o where o.rcd_id = d.id and o.status = 'issued'), 0)
       + coalesce((select sum(t.total) from rcr r join rcr_totals t on t.rcr_id = r.id where r.rcd_id = d.id), 0) as collections,
       coalesce((select sum(amount) from deposit x where x.rcd_id = d.id), 0) as deposits
from rcd d;

alter view rcr_totals set (security_invoker = true);
alter view rcd_totals set (security_invoker = true);

-- Section A of the RCD: the BT's ORs and the collectors' RCRs, in date and
-- number order. Cancelled ORs are listed with no amount.
create or replace function rcd_collection_lines(p_rcd uuid)
returns table (line_date date, number text, payor text, nature text, amount numeric, is_cancelled boolean, kind text, ref_id uuid)
language sql stable as $$
  select o.or_date, o.serial_no::text, o.payor, o.nature,
         case when o.status = 'cancelled' then null else o.amount end,
         o.status = 'cancelled', 'OR', o.id
  from official_receipt o where o.rcd_id = p_rcd
  union all
  select r.rcr_date, 'RCR ' || r.rcr_no, c.full_name, 'Collections per RCR',
         t.total, false, 'RCR', r.id
  from rcr r
  join official c on c.id = r.collector_official_id
  join rcr_totals t on t.rcr_id = r.id
  where r.rcd_id = p_rcd
  order by 1, 7, 2
$$;

-- Section C of the RCD / RCR: accountable forms as of the report date.
create or replace function report_accountable_forms(p_barangay uuid, p_date date, p_collector uuid default null)
returns table (
  form_name text, series text,
  beg_qty int, beg_from bigint, beg_to bigint,
  rec_qty int, rec_from bigint, rec_to bigint,
  iss_qty int, iss_from bigint, iss_to bigint,
  end_qty int, end_from bigint, end_to bigint)
language sql stable as $$
  with booklets as (
    select f.*,
           (select min(serial_no) from official_receipt o where o.accountable_form_id = f.id and o.or_date = p_date) as day_min,
           (select max(serial_no) from official_receipt o where o.accountable_form_id = f.id and o.or_date = p_date) as day_max,
           (select count(*)       from official_receipt o where o.accountable_form_id = f.id and o.or_date = p_date) as day_cnt,
           (select min(serial_no) from official_receipt o where o.accountable_form_id = f.id and o.or_date > p_date) as later_min
    from accountable_form f
    where f.barangay_id = p_barangay
      and f.form_type in ('official_receipt', 'cash_ticket')
      and (p_collector is null or f.issued_to_official_id = p_collector)
      and (f.received_on is null or f.received_on <= p_date)
  ),
  calc as (
    select b.form_name, b.series,
           -- first serial still on hand at the start of the day
           coalesce(b.day_min, b.later_min, b.next_serial) as start_from,
           b.serial_to,
           b.received_on = p_date as received_today,
           b.serial_from, b.day_cnt::int as iss_qty, b.day_min, b.day_max
    from booklets b
  )
  select form_name, series,
         case when received_today then 0 else greatest(serial_to - start_from + 1, 0)::int end,
         case when received_today then null else start_from end,
         case when received_today then null else serial_to end,
         case when received_today then (serial_to - serial_from + 1)::int else 0 end,
         case when received_today then serial_from end,
         case when received_today then serial_to end,
         iss_qty, day_min, day_max,
         greatest(serial_to - coalesce(day_max + 1, start_from) + 1, 0)::int,
         coalesce(day_max + 1, start_from),
         serial_to
  from calc
  order by form_name, series
$$;

-- ---------------------------------------------------------------------------
-- Posting the RCD to the Journal of Cash Transactions (4.3.1, 4.3.2).
-- One entry per fund for collections, one per fund and bank account for
-- deposits. Only the Accountant's office posts.
-- ---------------------------------------------------------------------------

create or replace function post_rcd(p_rcd uuid) returns setof journal_entry
language plpgsql as $$
declare
  v_rcd   rcd;
  v_fund  uuid;
  v_bank  uuid;
  v_entry journal_entry;
  v_line  int;
  v_total numeric(14,2);
  r       record;
begin
  select * into v_rcd from rcd where id = p_rcd for update;
  if v_rcd.id is null then
    raise exception 'RCD not found or not accessible';
  end if;
  if not is_lgu_staff(v_rcd.lgu_id) then
    raise exception 'only the C/M Accountant''s office posts an RCD' using errcode = '42501';
  end if;
  if v_rcd.status = 'draft' then
    raise exception 'the Treasurer must certify the RCD before it is posted';
  end if;
  if v_rcd.status = 'posted' then
    raise exception 'RCD % is already posted', v_rcd.rcd_no;
  end if;

  -- collections: Dr Cash - In Local Treasury / Cr income, liability or asset accounts
  for v_fund in
    select distinct o.fund_id
    from official_receipt o
    where o.status = 'issued'
      and (o.rcd_id = p_rcd or o.rcr_id in (select id from rcr where rcd_id = p_rcd))
  loop
    insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description, source_type, source_id)
    values (v_rcd.lgu_id, v_rcd.barangay_id, v_fund, 'JCT', v_rcd.rcd_date,
            format('To record collections per RCD No. %s', v_rcd.rcd_no), 'RCD', p_rcd)
    returning * into v_entry;

    select sum(o.amount) into v_total
    from official_receipt o
    where o.status = 'issued' and o.fund_id = v_fund
      and (o.rcd_id = p_rcd or o.rcr_id in (select id from rcr where rcd_id = p_rcd));

    insert into journal_line (entry_id, line_no, account_code, debit)
    values (v_entry.id, 1, '1-01-01-010', v_total);

    v_line := 1;
    for r in
      select ct.account_code, sum(o.amount) as amount
      from official_receipt o
      join collection_type ct on ct.id = o.collection_type_id
      where o.status = 'issued' and o.fund_id = v_fund
        and (o.rcd_id = p_rcd or o.rcr_id in (select id from rcr where rcd_id = p_rcd))
      group by ct.account_code
      order by ct.account_code
    loop
      v_line := v_line + 1;
      insert into journal_line (entry_id, line_no, account_code, credit)
      values (v_entry.id, v_line, r.account_code, r.amount);
    end loop;

    v_entry := post_journal_entry(v_entry.id);
    return next v_entry;
  end loop;

  -- deposits: Dr Cash in Bank / Cr Cash - In Local Treasury
  for v_fund, v_bank in
    select distinct x.fund_id, x.bank_account_id from deposit x where x.rcd_id = p_rcd
  loop
    insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description, source_type, source_id)
    values (v_rcd.lgu_id, v_rcd.barangay_id, v_fund, 'JCT', v_rcd.rcd_date,
            format('To record deposit of collections per RCD No. %s', v_rcd.rcd_no), 'RCD', p_rcd)
    returning * into v_entry;

    select sum(amount) into v_total from deposit where rcd_id = p_rcd and fund_id = v_fund and bank_account_id = v_bank;

    insert into journal_line (entry_id, line_no, account_code, debit, subsidiary_type, subsidiary_id, subsidiary_label)
    select v_entry.id, 1, b.gl_account_code, v_total, 'bank_account', b.id, b.bank_name || ' ' || b.account_number
    from bank_account b where b.id = v_bank;
    insert into journal_line (entry_id, line_no, account_code, credit)
    values (v_entry.id, 2, '1-01-01-010', v_total);

    v_entry := post_journal_entry(v_entry.id);
    return next v_entry;
  end loop;

  perform set_config('app.posting_rcd', p_rcd::text, true);
  update rcd set status = 'posted', posted_at = now(), posted_by = auth.uid() where id = p_rcd;
  perform set_config('app.posting_rcd', '', true);
  return;
end $$;

-- ---------------------------------------------------------------------------
-- Cashbook (Annex 8). cashbook_lines gathers every source; cashbook() adds
-- the beginning balance and running balances for one month.
-- ---------------------------------------------------------------------------

create or replace view cashbook_lines as
select d.barangay_id, d.rcd_date as entry_date, '1-' || d.rcd_no as sort_key,
       'Collections and Deposits'::text as particulars,
       'RCD No. ' || d.rcd_no as reference,
       t.collections as clt_collection,
       t.deposits    as clt_deposit,
       t.deposits    as cib_deposit,
       0::numeric    as cib_check,
       0::numeric    as ca_receipt,
       0::numeric    as ca_disbursement,
       0::numeric    as pc_receipt,
       0::numeric    as pc_payment
from rcd d
join rcd_totals t on t.rcd_id = d.id
where d.status in ('certified', 'posted');

alter view cashbook_lines set (security_invoker = true);

create or replace function cashbook(p_barangay uuid, p_year int, p_month int)
returns table (
  seq int, entry_date date, particulars text, reference text,
  clt_collection numeric, clt_deposit numeric, clt_balance numeric,
  cib_deposit numeric, cib_check numeric, cib_balance numeric,
  ca_receipt numeric, ca_disbursement numeric, ca_balance numeric,
  pc_receipt numeric, pc_payment numeric, pc_balance numeric)
language sql stable as $$
  with bounds as (
    select make_date(p_year, p_month, 1) as d_from, (make_date(p_year, p_month, 1) + interval '1 month')::date as d_to
  ),
  beg as (
    select coalesce(sum(l.clt_collection - l.clt_deposit), 0)  as clt,
           coalesce(sum(l.cib_deposit - l.cib_check), 0)       as cib,
           coalesce(sum(l.ca_receipt - l.ca_disbursement), 0)  as ca,
           coalesce(sum(l.pc_receipt - l.pc_payment), 0)       as pc
    from cashbook_lines l, bounds b
    where l.barangay_id = p_barangay and l.entry_date < b.d_from
  ),
  month_lines as (
    select l.*, row_number() over (order by l.entry_date, l.sort_key)::int as rn
    from cashbook_lines l, bounds b
    where l.barangay_id = p_barangay and l.entry_date >= b.d_from and l.entry_date < b.d_to
  )
  select 0, b.d_from, 'Bal. Beginning', null,
         null, null, beg.clt, null, null, beg.cib, null, null, beg.ca, null, null, beg.pc
  from beg, bounds b
  union all
  select m.rn, m.entry_date, m.particulars, m.reference,
         m.clt_collection, m.clt_deposit,
         beg.clt + sum(m.clt_collection - m.clt_deposit) over (order by m.rn),
         m.cib_deposit, m.cib_check,
         beg.cib + sum(m.cib_deposit - m.cib_check) over (order by m.rn),
         m.ca_receipt, m.ca_disbursement,
         beg.ca + sum(m.ca_receipt - m.ca_disbursement) over (order by m.rn),
         m.pc_receipt, m.pc_payment,
         beg.pc + sum(m.pc_receipt - m.pc_payment) over (order by m.rn)
  from month_lines m, beg
  order by 1
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table collection_type enable row level security;
create policy collection_type_select on collection_type for select to authenticated using (has_lgu_access(lgu_id));
create policy collection_type_write on collection_type for all to authenticated
  using (is_lgu_staff(lgu_id)) with check (is_lgu_staff(lgu_id));

do $$
declare t text;
begin
  foreach t in array array['rcd', 'rcr', 'official_receipt', 'deposit']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I_select on %I for select to authenticated using (can_read(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_insert on %I for insert to authenticated with check (can_write(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_update on %I for update to authenticated using (can_write(lgu_id, barangay_id)) with check (can_write(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_delete on %I for delete to authenticated using (can_write(lgu_id, barangay_id))', t, t);
  end loop;
end $$;

grant select, insert, update, delete on collection_type, rcd, rcr, official_receipt, deposit to authenticated, service_role;
grant select on rcr_totals, rcd_totals, cashbook_lines to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;
revoke all on all functions in schema public from anon;
