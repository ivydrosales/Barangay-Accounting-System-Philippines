-- Phase 1, migration 6: disbursements by check (manual Chapter V, 5.2.1;
-- Annexes 12 and 16; COA Circular 2012-005 for the PB Certification).
--
--   Disbursement Voucher (Annex 12): prepared by the BT with its Box E
--   lines (what is charged, what is withheld); then Box A (CCA), Box B (BT),
--   Box C (PB) in that order, each by a login holding that role; then the
--   check, taken in serial order from a check booklet, with its PB
--   Certification; then Box D when the payee receives the check. The
--   Accountant posts paid DVs to the JCT per 5.3.1(a).
--   Transmittal Letter (Annex 16): the BT's monthly cover list of paid DVs
--   (with check and PBC), RCDs and other reports to the Accountant.
--   Cashbook: checks issued appear under Cash in Bank - Check Issued.
--
-- Not yet here (later phases): the RAO hard stop behind Box A, bank-balance
-- checks behind Box B (they need opening balances and bank credit memos),
-- payroll and cash advances, spoiled/stale check handling, the RAAF.

create type dv_status as enum ('draft', 'certified_a', 'certified_b', 'approved', 'check_issued', 'paid', 'cancelled');
create type dv_line_kind as enum ('charge', 'deduction');
create type check_status as enum ('issued', 'released', 'cleared', 'stale', 'spoiled', 'cancelled');
create type transmittal_status as enum ('draft', 'submitted', 'received');

-- Does the signed-in user hold this role in this barangay?
create or replace function has_barangay_role(p_barangay uuid, p_role app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_membership m
    where m.user_id = auth.uid() and m.is_active and m.barangay_id = p_barangay and m.role = p_role
  )
$$;

-- The current holder of a position in a barangay, for signature blocks.
create or replace function barangay_official(p_barangay uuid, p_position text) returns official
language sql stable security definer set search_path = public as $$
  select * from official
  where barangay_id = p_barangay and is_active and position = p_position
  order by term_start desc nulls last, created_at desc
  limit 1
$$;

-- ---------------------------------------------------------------------------
-- Disbursement Voucher
-- ---------------------------------------------------------------------------

create table disbursement_voucher (
  id                 uuid primary key default gen_random_uuid(),
  lgu_id             uuid not null references lgu(id),
  barangay_id        uuid not null references barangay(id),
  fund_id            uuid not null references fund(id),
  dv_no              text not null,
  dv_date            date not null,
  payee              text not null,
  payee_tin          text,
  payee_address      text,
  supplier_id        uuid references supplier(id),
  employee_id        uuid references employee(id),
  particulars        text not null,
  amount             numeric(14,2) not null check (amount > 0),     -- gross claim (Box "Amount")
  -- Box A: CCA, existence of appropriation
  box_a_official_id  uuid references official(id),
  box_a_by           uuid,
  box_a_at           timestamptz,
  -- Box B: BT, availability of funds and completeness of documents
  box_b_official_id  uuid references official(id),
  box_b_by           uuid,
  box_b_at           timestamptz,
  -- Box C: PB, validity, propriety and legality; approval
  box_c_official_id  uuid references official(id),
  box_c_by           uuid,
  box_c_at           timestamptz,
  -- Box D: payee's receipt of the check
  received_by        text,
  received_on        date,
  payee_or_no        text,
  status             dv_status not null default 'draft',
  cancelled_reason   text,
  cancelled_at       timestamptz,
  cancelled_by       uuid,
  transmittal_id     uuid,                                           -- fk added below
  created_by         uuid default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  foreign key (fund_id, barangay_id) references fund(id, barangay_id),
  unique (barangay_id, dv_no)
);

create index on disbursement_voucher (barangay_id, dv_date);
create index on disbursement_voucher (barangay_id, status);

-- Box E as prepared with the voucher: charges are debited (expense, asset
-- or a payable being settled); deductions are credited (Due to BIR and the
-- like). Net of deductions = the check.
create table dv_line (
  id           uuid primary key default gen_random_uuid(),
  dv_id        uuid not null references disbursement_voucher(id) on delete cascade,
  line_no      int not null check (line_no > 0),
  kind         dv_line_kind not null,
  account_code text not null references account(code),
  amount       numeric(14,2) not null check (amount > 0),
  particulars  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (dv_id, line_no)
);

create or replace view dv_totals as
select d.id as dv_id,
       coalesce(sum(l.amount) filter (where l.kind = 'charge'), 0)    as charges,
       coalesce(sum(l.amount) filter (where l.kind = 'deduction'), 0) as deductions,
       coalesce(sum(l.amount) filter (where l.kind = 'charge'), 0)
       - coalesce(sum(l.amount) filter (where l.kind = 'deduction'), 0) as net_amount
from disbursement_voucher d
left join dv_line l on l.dv_id = d.id
group by d.id;

alter view dv_totals set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- Checks and the PB Certification
-- ---------------------------------------------------------------------------

create table bank_check (
  id                  uuid primary key default gen_random_uuid(),
  lgu_id              uuid not null references lgu(id),
  barangay_id         uuid not null references barangay(id),
  bank_account_id     uuid not null references bank_account(id),
  accountable_form_id uuid not null references accountable_form(id),   -- the check booklet
  dv_id               uuid not null references disbursement_voucher(id),
  check_no            bigint not null,
  check_date          date not null,
  payee               text not null,
  amount              numeric(14,2) not null check (amount > 0),
  pbc_no              text not null,                                   -- PB Certification, COA Circular 2012-005
  pbc_date            date not null,
  status              check_status not null default 'issued',
  released_on         date,
  created_by          uuid default auth.uid(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (accountable_form_id, check_no),
  unique (dv_id)
);

create index on bank_check (barangay_id, check_date);

-- ---------------------------------------------------------------------------
-- Transmittal Letter
-- ---------------------------------------------------------------------------

create table transmittal_letter (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  tl_no                 text,                                          -- assigned when submitted
  tl_date               date not null,
  period_year           int not null,
  period_month          int not null check (period_month between 1 and 12),
  treasurer_official_id uuid references official(id),
  noted_by_official_id  uuid references official(id),
  status                transmittal_status not null default 'draft',
  submitted_at          timestamptz,
  received_by           text,
  received_at           timestamptz,
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, tl_no),
  constraint tl_numbered_when_submitted check ((status = 'draft') = (tl_no is null))
);

create table tl_other_report (
  id             uuid primary key default gen_random_uuid(),
  transmittal_id uuid not null references transmittal_letter(id) on delete cascade,
  report_date    date not null,
  report_type    text not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table disbursement_voucher add foreign key (transmittal_id) references transmittal_letter(id) on delete set null;
alter table rcd add column transmittal_id uuid references transmittal_letter(id) on delete set null;

do $$
declare t text;
begin
  foreach t in array array['disbursement_voucher', 'dv_line', 'bank_check', 'transmittal_letter', 'tl_other_report']
  loop
    execute format('create trigger %I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
    execute format('create trigger %I_audit after insert or update or delete on %I for each row execute function write_audit_log()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

create or replace function tl_is_frozen(p_tl uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from transmittal_letter where id = p_tl and status <> 'draft')
$$;

-- A DV is edited only while a draft; after Box A it moves only through the
-- step functions (flag app.dv_step). It is never deleted: cancel it instead,
-- and the number stays in the series.
create or replace function dv_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'DV % cannot be deleted; cancel it instead', old.dv_no using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    if current_setting('app.creating_dv', true) is distinct from new.barangay_id::text then
      raise exception 'use create_dv() so voucher numbers stay in sequence' using errcode = 'P0001';
    end if;
    return new;
  end if;

  if (new.dv_no, new.barangay_id, new.lgu_id) is distinct from (old.dv_no, old.barangay_id, old.lgu_id) then
    raise exception 'DV % keeps its number and barangay', old.dv_no using errcode = 'P0001';
  end if;
  if current_setting('app.dv_step', true) = old.id::text then
    return new;   -- a step function is moving it along
  end if;
  if old.transmittal_id is not null and tl_is_frozen(old.transmittal_id) then
    raise exception 'DV % is on a submitted Transmittal Letter', old.dv_no using errcode = 'P0001';
  end if;
  if new.transmittal_id is distinct from old.transmittal_id then
    if new.transmittal_id is not null and tl_is_frozen(new.transmittal_id) then
      raise exception 'cannot add DV % to a submitted Transmittal Letter', old.dv_no using errcode = 'P0001';
    end if;
    if to_jsonb(new) - 'transmittal_id' - 'updated_at' = to_jsonb(old) - 'transmittal_id' - 'updated_at' then
      return new;
    end if;
  end if;
  if old.status <> 'draft' then
    raise exception 'DV % is % and can only move through its boxes', old.dv_no, old.status using errcode = 'P0001';
  end if;
  if new.status <> 'draft'
     or (new.box_a_at, new.box_b_at, new.box_c_at, new.received_on) is distinct from (old.box_a_at, old.box_b_at, old.box_c_at, old.received_on) then
    raise exception 'boxes are signed with certify_dv_box_a/b, approve_dv and release_check' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger dv_guard before insert or update or delete on disbursement_voucher
  for each row execute function dv_guard();

create or replace function dv_line_guard() returns trigger
language plpgsql as $$
declare
  v_dv    disbursement_voucher;
  v_class account_class;
begin
  select * into v_dv from disbursement_voucher where id = coalesce(new.dv_id, old.dv_id);
  if v_dv.id is null then
    return coalesce(new, old);   -- parent gone (cascade)
  end if;
  if v_dv.status <> 'draft' then
    raise exception 'DV % is %; its lines are frozen', v_dv.dv_no, v_dv.status using errcode = 'P0001';
  end if;
  if tg_op <> 'DELETE' then
    select class into v_class from account where code = new.account_code and is_active;
    if v_class is null then
      raise exception 'account % is not an active chart account', new.account_code using errcode = 'P0001';
    end if;
    if new.kind = 'charge' and v_class not in ('Expense', 'Asset', 'Liability') then
      raise exception 'a DV charges an expense, asset or payable account; % is %', new.account_code, v_class using errcode = 'P0001';
    end if;
    if new.kind = 'deduction' and v_class <> 'Liability' then
      raise exception 'a deduction is withheld to a liability account such as Due to BIR; % is %', new.account_code, v_class using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end $$;

create trigger dv_line_guard before insert or update or delete on dv_line
  for each row execute function dv_line_guard();

create or replace function bank_check_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'check % is never deleted; spoil or cancel it', old.check_no using errcode = 'P0001';
  end if;
  if tg_op = 'INSERT' then
    if current_setting('app.issuing_check', true) is distinct from new.dv_id::text then
      raise exception 'use issue_check() so check numbers stay in sequence' using errcode = 'P0001';
    end if;
    return new;
  end if;
  if current_setting('app.check_step', true) = old.id::text then
    return new;
  end if;
  raise exception 'check % changes only through release_check()', old.check_no using errcode = 'P0001';
end $$;

create trigger bank_check_guard before insert or update or delete on bank_check
  for each row execute function bank_check_guard();

create or replace function transmittal_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'Transmittal Letter % is submitted and cannot be deleted', old.tl_no using errcode = 'P0001';
    end if;
    return old;
  end if;
  if current_setting('app.tl_step', true) = old.id::text then
    return new;
  end if;
  if old.status <> 'draft' or new.status <> 'draft' then
    raise exception 'Transmittal Letter % changes only through submit_transmittal() and receive_transmittal()', coalesce(old.tl_no, '(draft)') using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger transmittal_guard before update or delete on transmittal_letter
  for each row execute function transmittal_guard();

create or replace function tl_other_report_guard() returns trigger
language plpgsql as $$
begin
  if tl_is_frozen(coalesce(new.transmittal_id, old.transmittal_id)) then
    raise exception 'the Transmittal Letter is submitted; its list is frozen' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end $$;

create trigger tl_other_report_guard before insert or update or delete on tl_other_report
  for each row execute function tl_other_report_guard();

-- Accountable form booklets (ORs, cash tickets, checks) now have their own
-- screen. Serials leave a booklet one at a time, in order, and only when a
-- receipt or check with that number exists; a booklet that has issued
-- serials keeps its range; used-up, returned and lost booklets stay so.
create or replace function accountable_form_guard() returns trigger
language plpgsql as $$
begin
  if old.next_serial > old.serial_from
     and (new.barangay_id, new.lgu_id, new.form_type, new.serial_from, new.serial_to)
         is distinct from (old.barangay_id, old.lgu_id, old.form_type, old.serial_from, old.serial_to) then
    raise exception 'booklet % has issued serials; its range cannot change', coalesce(old.series, old.form_name) using errcode = 'P0001';
  end if;
  if new.next_serial is distinct from old.next_serial
     and not (old.next_serial = old.serial_from and new.next_serial = new.serial_from)   -- correcting an unused booklet
     and (new.next_serial <> old.next_serial + 1
          or not (exists (select 1 from official_receipt where accountable_form_id = old.id and serial_no = old.next_serial)
                  or exists (select 1 from bank_check where accountable_form_id = old.id and check_no = old.next_serial))) then
    raise exception 'serials are issued one at a time and in order; No. % has not been issued', old.next_serial using errcode = 'P0001';
  end if;
  if old.status in ('used_up', 'returned', 'lost') and new.status <> old.status then
    raise exception 'booklet % is %; that cannot be undone', coalesce(old.series, old.form_name), replace(old.status::text, '_', ' ') using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger accountable_form_guard before update on accountable_form
  for each row execute function accountable_form_guard();

-- The RCD's transmittal link follows the same rule; the RCD guard allows
-- this one column to change on a certified RCD.
create or replace function rcd_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'RCD % is certified and cannot be deleted', old.rcd_no using errcode = 'P0001';
    end if;
    return old;
  end if;

  if new.transmittal_id is distinct from old.transmittal_id then
    if old.transmittal_id is not null and tl_is_frozen(old.transmittal_id) then
      raise exception 'RCD % is on a submitted Transmittal Letter', old.rcd_no using errcode = 'P0001';
    end if;
    if new.transmittal_id is not null and (tl_is_frozen(new.transmittal_id) or old.status = 'draft') then
      raise exception 'only certified RCDs go on an open Transmittal Letter' using errcode = 'P0001';
    end if;
    if to_jsonb(new) - 'transmittal_id' - 'updated_at' = to_jsonb(old) - 'transmittal_id' - 'updated_at' then
      return new;
    end if;
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

-- ---------------------------------------------------------------------------
-- Preparing the voucher
-- ---------------------------------------------------------------------------

-- p_lines: [{"kind":"charge","account_code":"5-02-03-010","amount":1000,"particulars":"..."}, {"kind":"deduction", ...}]
create or replace function create_dv(
  p_barangay      uuid,
  p_fund          uuid,
  p_date          date,
  p_payee         text,
  p_particulars   text,
  p_lines         jsonb,
  p_payee_tin     text default null,
  p_payee_address text default null,
  p_supplier      uuid default null,
  p_employee      uuid default null
) returns disbursement_voucher
language plpgsql as $$
declare
  v_lgu  uuid;
  v_dv   disbursement_voucher;
  v_gross numeric(14,2);
  v_net   numeric(14,2);
  r       record;
  v_n     int := 0;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'barangay not found or not accessible';
  end if;
  if coalesce(trim(p_payee), '') = '' then
    raise exception 'the payee is required';
  end if;
  if coalesce(trim(p_particulars), '') = '' then
    raise exception 'particulars are required';
  end if;
  if is_period_closed(p_barangay, p_date) then
    raise exception 'period is closed for %', p_date;
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'at least one charge line is required';
  end if;

  select coalesce(sum((l ->> 'amount')::numeric) filter (where l ->> 'kind' = 'charge'), 0),
         coalesce(sum((l ->> 'amount')::numeric) filter (where l ->> 'kind' = 'charge'), 0)
         - coalesce(sum((l ->> 'amount')::numeric) filter (where l ->> 'kind' = 'deduction'), 0)
  into v_gross, v_net
  from jsonb_array_elements(p_lines) l;
  if v_gross <= 0 then
    raise exception 'the charges must add up to more than zero';
  end if;
  if v_net <= 0 then
    raise exception 'deductions cannot equal or exceed the amount of the claim';
  end if;

  perform set_config('app.creating_dv', p_barangay::text, true);
  insert into disbursement_voucher (lgu_id, barangay_id, fund_id, dv_no, dv_date, payee, payee_tin, payee_address,
                                    supplier_id, employee_id, particulars, amount)
  values (v_lgu, p_barangay, p_fund, next_document_number(p_barangay, 'DV', p_date), p_date, trim(p_payee),
          nullif(trim(p_payee_tin), ''), nullif(trim(p_payee_address), ''), p_supplier, p_employee, trim(p_particulars), v_gross)
  returning * into v_dv;
  perform set_config('app.creating_dv', '', true);

  for r in select value as l from jsonb_array_elements(p_lines) loop
    v_n := v_n + 1;
    insert into dv_line (dv_id, line_no, kind, account_code, amount, particulars)
    values (v_dv.id, v_n, (r.l ->> 'kind')::dv_line_kind, r.l ->> 'account_code', (r.l ->> 'amount')::numeric, r.l ->> 'particulars');
  end loop;

  return v_dv;
end $$;

create or replace function cancel_dv(p_dv uuid, p_reason text) returns disbursement_voucher
language plpgsql as $$
declare v_dv disbursement_voucher;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if v_dv.status = 'cancelled' then
    return v_dv;
  end if;
  if v_dv.status in ('check_issued', 'paid') then
    raise exception 'DV % already has a check; spoil or cancel the check first', v_dv.dv_no;
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'a reason is required to cancel a DV';
  end if;
  perform set_config('app.dv_step', p_dv::text, true);
  update disbursement_voucher
  set status = 'cancelled', cancelled_reason = trim(p_reason), cancelled_at = now(), cancelled_by = auth.uid()
  where id = p_dv
  returning * into v_dv;
  perform set_config('app.dv_step', '', true);
  return v_dv;
end $$;

-- ---------------------------------------------------------------------------
-- Boxes A, B, C: each by the login holding that role in the barangay
-- ---------------------------------------------------------------------------

create or replace function certify_dv_box_a(p_dv uuid) returns disbursement_voucher
language plpgsql as $$
declare
  v_dv disbursement_voucher;
  v_t  dv_totals;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if v_dv.status <> 'draft' then
    raise exception 'DV % is %; Box A is signed on a draft', v_dv.dv_no, v_dv.status;
  end if;
  if not has_barangay_role(v_dv.barangay_id, 'cca') then
    raise exception 'Box A is certified by the Chairman of the Committee on Appropriations' using errcode = '42501';
  end if;
  select * into v_t from dv_totals where dv_id = p_dv;
  if v_t.charges <> v_dv.amount then
    raise exception 'the charges (%) must equal the amount of the claim (%)', v_t.charges, v_dv.amount;
  end if;
  -- Phase 2 adds the RAO check here: obligation <= available appropriation (3.1.1).

  perform set_config('app.dv_step', p_dv::text, true);
  update disbursement_voucher
  set status = 'certified_a', box_a_by = auth.uid(), box_a_at = now(),
      box_a_official_id = (barangay_official(barangay_id, 'Chairman, Committee on Appropriations')).id
  where id = p_dv
  returning * into v_dv;
  perform set_config('app.dv_step', '', true);
  return v_dv;
end $$;

create or replace function certify_dv_box_b(p_dv uuid) returns disbursement_voucher
language plpgsql as $$
declare v_dv disbursement_voucher;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if v_dv.status <> 'certified_a' then
    raise exception 'DV % needs Box A (CCA) before Box B', v_dv.dv_no;
  end if;
  if not has_barangay_role(v_dv.barangay_id, 'barangay_treasurer') then
    raise exception 'Box B is certified by the Barangay Treasurer' using errcode = '42501';
  end if;

  perform set_config('app.dv_step', p_dv::text, true);
  update disbursement_voucher
  set status = 'certified_b', box_b_by = auth.uid(), box_b_at = now(),
      box_b_official_id = (barangay_official(barangay_id, 'Barangay Treasurer')).id
  where id = p_dv
  returning * into v_dv;
  perform set_config('app.dv_step', '', true);
  return v_dv;
end $$;

create or replace function approve_dv(p_dv uuid) returns disbursement_voucher
language plpgsql as $$
declare v_dv disbursement_voucher;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if v_dv.status <> 'certified_b' then
    raise exception 'DV % needs Boxes A and B before the Punong Barangay approves it', v_dv.dv_no;
  end if;
  if not has_barangay_role(v_dv.barangay_id, 'punong_barangay') then
    raise exception 'Box C is signed by the Punong Barangay' using errcode = '42501';
  end if;

  perform set_config('app.dv_step', p_dv::text, true);
  update disbursement_voucher
  set status = 'approved', box_c_by = auth.uid(), box_c_at = now(),
      box_c_official_id = (barangay_official(barangay_id, 'Punong Barangay')).id
  where id = p_dv
  returning * into v_dv;
  perform set_config('app.dv_step', '', true);
  return v_dv;
end $$;

-- ---------------------------------------------------------------------------
-- The check and the PB Certification
-- ---------------------------------------------------------------------------

create or replace function issue_check(p_dv uuid, p_check_booklet uuid, p_check_date date) returns bank_check
language plpgsql as $$
declare
  v_dv    disbursement_voucher;
  v_form  accountable_form;
  v_t     dv_totals;
  v_bank  bank_account;
  v_check bank_check;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if v_dv.status <> 'approved' then
    raise exception 'DV % must carry Boxes A, B and C before a check is drawn (5.1.3)', v_dv.dv_no;
  end if;
  if not has_barangay_role(v_dv.barangay_id, 'barangay_treasurer') then
    raise exception 'checks are prepared by the Barangay Treasurer' using errcode = '42501';
  end if;
  if is_period_closed(v_dv.barangay_id, p_check_date) then
    raise exception 'period is closed for %', p_check_date;
  end if;

  select * into v_form from accountable_form where id = p_check_booklet for update;
  if v_form.id is null or v_form.barangay_id <> v_dv.barangay_id or v_form.form_type <> 'check' then
    raise exception 'check booklet not found for this barangay';
  end if;
  if v_form.status not in ('on_hand', 'in_use') or v_form.next_serial > v_form.serial_to then
    raise exception 'check booklet % is used up or not available', v_form.series;
  end if;

  select * into v_bank from bank_account
  where barangay_id = v_dv.barangay_id and is_depository and closed_on is null;
  if v_bank.id is null then
    raise exception 'the barangay has no depository bank account on record';
  end if;

  select * into v_t from dv_totals where dv_id = p_dv;

  perform set_config('app.issuing_check', p_dv::text, true);
  insert into bank_check (lgu_id, barangay_id, bank_account_id, accountable_form_id, dv_id, check_no, check_date,
                          payee, amount, pbc_no, pbc_date)
  values (v_dv.lgu_id, v_dv.barangay_id, v_bank.id, v_form.id, p_dv, v_form.next_serial, p_check_date,
          v_dv.payee, v_t.net_amount, next_document_number(v_dv.barangay_id, 'PBC', p_check_date), p_check_date)
  returning * into v_check;
  perform set_config('app.issuing_check', '', true);

  update accountable_form
  set next_serial = next_serial + 1,
      status      = case when next_serial + 1 > serial_to then 'used_up'::accountable_form_status else 'in_use' end
  where id = v_form.id;

  perform set_config('app.dv_step', p_dv::text, true);
  update disbursement_voucher set status = 'check_issued' where id = p_dv;
  perform set_config('app.dv_step', '', true);

  return v_check;
end $$;

-- Box D: the payee receives the check.
create or replace function release_check(p_dv uuid, p_received_by text, p_received_on date, p_payee_or_no text default null)
returns disbursement_voucher
language plpgsql as $$
declare
  v_dv    disbursement_voucher;
  v_check bank_check;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if v_dv.status <> 'check_issued' then
    raise exception 'DV % has no check to release', v_dv.dv_no;
  end if;
  if coalesce(trim(p_received_by), '') = '' then
    raise exception 'the name of the person receiving the check is required';
  end if;
  select * into v_check from bank_check where dv_id = p_dv;
  if p_received_on < v_check.check_date then
    raise exception 'a check cannot be received before its date';
  end if;

  perform set_config('app.check_step', v_check.id::text, true);
  update bank_check set status = 'released', released_on = p_received_on where id = v_check.id;
  perform set_config('app.check_step', '', true);

  perform set_config('app.dv_step', p_dv::text, true);
  update disbursement_voucher
  set status = 'paid', received_by = trim(p_received_by), received_on = p_received_on, payee_or_no = nullif(trim(p_payee_or_no), '')
  where id = p_dv
  returning * into v_dv;
  perform set_config('app.dv_step', '', true);
  return v_dv;
end $$;

-- ---------------------------------------------------------------------------
-- Posting a paid DV to the JCT: Dr charges / Cr deductions / Cr Cash in Bank (5.3.1 a)
-- ---------------------------------------------------------------------------

create or replace function post_dv(p_dv uuid) returns journal_entry
language plpgsql as $$
declare
  v_dv    disbursement_voucher;
  v_check bank_check;
  v_bank  bank_account;
  v_entry journal_entry;
  v_line  int := 0;
  r       record;
begin
  select * into v_dv from disbursement_voucher where id = p_dv for update;
  if v_dv.id is null then
    raise exception 'DV not found or not accessible';
  end if;
  if not is_lgu_staff(v_dv.lgu_id) then
    raise exception 'only the C/M Accountant''s office posts a DV' using errcode = '42501';
  end if;
  if v_dv.status <> 'paid' then
    raise exception 'DV % is %; only paid vouchers are posted', v_dv.dv_no, v_dv.status;
  end if;
  if exists (select 1 from journal_entry where source_type = 'DV' and source_id = p_dv and status <> 'reversed') then
    raise exception 'DV % is already posted', v_dv.dv_no;
  end if;

  select * into v_check from bank_check where dv_id = p_dv;
  select * into v_bank from bank_account where id = v_check.bank_account_id;

  insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description, source_type, source_id)
  values (v_dv.lgu_id, v_dv.barangay_id, v_dv.fund_id, 'JCT', v_check.check_date,
          format('DV No. %s, Check No. %s: %s', v_dv.dv_no, v_check.check_no, v_dv.particulars), 'DV', p_dv)
  returning * into v_entry;

  for r in
    select kind, account_code, sum(amount) as amount
    from dv_line where dv_id = p_dv
    group by kind, account_code
    order by kind, account_code          -- charges first (enum order), then deductions
  loop
    v_line := v_line + 1;
    insert into journal_line (entry_id, line_no, account_code, debit, credit, subsidiary_type, subsidiary_id, subsidiary_label)
    values (v_entry.id, v_line, r.account_code,
            case when r.kind = 'charge' then r.amount else 0 end,
            case when r.kind = 'deduction' then r.amount else 0 end,
            case when r.kind = 'charge' and v_dv.supplier_id is not null then 'supplier' end,
            case when r.kind = 'charge' then v_dv.supplier_id end,
            case when r.kind = 'charge' then v_dv.payee end);
  end loop;

  v_line := v_line + 1;
  insert into journal_line (entry_id, line_no, account_code, credit, subsidiary_type, subsidiary_id, subsidiary_label)
  values (v_entry.id, v_line, v_bank.gl_account_code, v_check.amount, 'bank_account', v_bank.id, v_bank.bank_name || ' ' || v_bank.account_number);

  return post_journal_entry(v_entry.id);
end $$;

-- ---------------------------------------------------------------------------
-- Transmittal Letter (Annex 16)
-- ---------------------------------------------------------------------------

create or replace function prepare_transmittal(p_barangay uuid, p_year int, p_month int, p_date date default null)
returns transmittal_letter
language plpgsql as $$
declare
  v_lgu  uuid;
  v_tl   transmittal_letter;
  v_from date := make_date(p_year, p_month, 1);
  v_to   date := (make_date(p_year, p_month, 1) + interval '1 month')::date;
  v_dvs  int; v_rcds int;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'barangay not found or not accessible';
  end if;
  if exists (select 1 from transmittal_letter where barangay_id = p_barangay and status = 'draft') then
    raise exception 'there is already a draft Transmittal Letter; submit or delete it first';
  end if;

  insert into transmittal_letter (lgu_id, barangay_id, tl_date, period_year, period_month, treasurer_official_id, noted_by_official_id)
  values (v_lgu, p_barangay, coalesce(p_date, manila_today()), p_year, p_month,
          (barangay_official(p_barangay, 'Barangay Treasurer')).id,
          (barangay_official(p_barangay, 'Punong Barangay')).id)
  returning * into v_tl;

  update disbursement_voucher d set transmittal_id = v_tl.id
  from bank_check c
  where c.dv_id = d.id and d.barangay_id = p_barangay and d.status = 'paid' and d.transmittal_id is null
    and c.check_date >= v_from and c.check_date < v_to;
  get diagnostics v_dvs = row_count;

  update rcd set transmittal_id = v_tl.id
  where barangay_id = p_barangay and status in ('certified', 'posted') and transmittal_id is null
    and rcd_date >= v_from and rcd_date < v_to;
  get diagnostics v_rcds = row_count;

  if v_dvs + v_rcds = 0 then
    raise exception 'nothing to transmit for %-%: no paid DVs or certified RCDs', p_year, lpad(p_month::text, 2, '0');
  end if;
  return v_tl;
end $$;

create or replace function submit_transmittal(p_tl uuid) returns transmittal_letter
language plpgsql as $$
declare v_tl transmittal_letter;
begin
  select * into v_tl from transmittal_letter where id = p_tl for update;
  if v_tl.id is null then
    raise exception 'Transmittal Letter not found or not accessible';
  end if;
  if v_tl.status <> 'draft' then
    return v_tl;
  end if;
  perform set_config('app.tl_step', p_tl::text, true);
  update transmittal_letter
  set status = 'submitted', submitted_at = now(), tl_no = next_document_number(v_tl.barangay_id, 'TL', v_tl.tl_date)
  where id = p_tl
  returning * into v_tl;
  perform set_config('app.tl_step', '', true);
  return v_tl;
end $$;

create or replace function receive_transmittal(p_tl uuid, p_received_by text) returns transmittal_letter
language plpgsql as $$
declare v_tl transmittal_letter;
begin
  select * into v_tl from transmittal_letter where id = p_tl for update;
  if v_tl.id is null then
    raise exception 'Transmittal Letter not found or not accessible';
  end if;
  if not is_lgu_staff(v_tl.lgu_id) then
    raise exception 'the Accountant''s office acknowledges receipt' using errcode = '42501';
  end if;
  if v_tl.status = 'draft' then
    raise exception 'the Treasurer must submit the Transmittal Letter first';
  end if;
  if v_tl.status = 'received' then
    return v_tl;
  end if;
  perform set_config('app.tl_step', p_tl::text, true);
  update transmittal_letter
  set status = 'received', received_by = trim(p_received_by), received_at = now()
  where id = p_tl
  returning * into v_tl;
  perform set_config('app.tl_step', '', true);
  return v_tl;
end $$;

-- ---------------------------------------------------------------------------
-- Cashbook: checks issued join the RCD rows
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
where d.status in ('certified', 'posted')
union all
select c.barangay_id, c.check_date, '2-' || lpad(c.check_no::text, 12, '0'),
       v.payee || ' – ' || left(v.particulars, 80),
       'Check No. ' || c.check_no || ' / DV ' || v.dv_no,
       0, 0, 0, c.amount, 0, 0, 0, 0
from bank_check c
join disbursement_voucher v on v.id = c.dv_id
where c.status in ('issued', 'released', 'cleared', 'stale');

alter view cashbook_lines set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- Row-level security and grants
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['disbursement_voucher', 'bank_check', 'transmittal_letter']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I_select on %I for select to authenticated using (can_read(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_insert on %I for insert to authenticated with check (can_write(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_update on %I for update to authenticated using (can_write(lgu_id, barangay_id)) with check (can_write(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_delete on %I for delete to authenticated using (can_write(lgu_id, barangay_id))', t, t);
  end loop;
end $$;

alter table dv_line enable row level security;
create policy dv_line_select on dv_line for select to authenticated
  using (exists (select 1 from disbursement_voucher d where d.id = dv_line.dv_id and can_read(d.lgu_id, d.barangay_id)));
create policy dv_line_write on dv_line for all to authenticated
  using (exists (select 1 from disbursement_voucher d where d.id = dv_line.dv_id and can_write(d.lgu_id, d.barangay_id)))
  with check (exists (select 1 from disbursement_voucher d where d.id = dv_line.dv_id and can_write(d.lgu_id, d.barangay_id)));

alter table tl_other_report enable row level security;
create policy tl_other_report_select on tl_other_report for select to authenticated
  using (exists (select 1 from transmittal_letter t where t.id = tl_other_report.transmittal_id and can_read(t.lgu_id, t.barangay_id)));
create policy tl_other_report_write on tl_other_report for all to authenticated
  using (exists (select 1 from transmittal_letter t where t.id = tl_other_report.transmittal_id and can_write(t.lgu_id, t.barangay_id)))
  with check (exists (select 1 from transmittal_letter t where t.id = tl_other_report.transmittal_id and can_write(t.lgu_id, t.barangay_id)));

grant select, insert, update, delete on disbursement_voucher, dv_line, bank_check, transmittal_letter, tl_other_report to authenticated, service_role;
grant select on dv_totals to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;
revoke all on all functions in schema public from anon;
