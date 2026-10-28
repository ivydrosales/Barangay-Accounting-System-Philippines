-- Phase 1, migration 7: Report of Accountability for Accountable Forms
-- (RAAF, Annex 18; manual 4.1.9, 4.2.10, 8.1.17).
--
--   One RAAF per barangay per month for all accountable forms: cash tickets
--   (section A, with money value), Official Receipts and checks (section B,
--   without money value). For each booklet: beginning balance, receipts,
--   issuances and ending balance, each as a quantity and inclusive serials.
--   While a draft, the lines are computed live from the booklets, ORs and
--   checks; certifying by the Barangay Treasurer numbers the report
--   (YYYY-MM-NNN, the month reported) and stores the lines as certified.
--
--   A booklet returned to the C/M Treasurer or reported lost now records the
--   date (disposed_on); its unused serials are reported as issued that month.
--
-- Not yet here: separate RAAFs for Deputized Barangay Collectors (4.1.9),
-- spoiled checks (8.1.17) until spoiled-check handling is built.

alter table accountable_form add column disposed_on date;

-- Same rules as migration 6, plus: marking a booklet returned or lost
-- stamps the date, which the RAAF needs.
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
  if new.status in ('returned', 'lost') and old.status not in ('returned', 'lost') then
    new.disposed_on := coalesce(new.disposed_on, manila_today());
  elsif new.disposed_on is distinct from old.disposed_on then
    raise exception 'the date a booklet was returned or lost is set when it is marked so' using errcode = 'P0001';
  end if;
  return new;
end $$;

create type raaf_status as enum ('draft', 'certified');

create table raaf (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  raaf_no               text,                                          -- assigned when certified
  period_year           int not null,
  period_month          int not null check (period_month between 1 and 12),
  treasurer_official_id uuid references official(id),
  status                raaf_status not null default 'draft',
  certified_at          timestamptz,
  certified_by          uuid,
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, period_year, period_month),
  unique (barangay_id, raaf_no),
  constraint raaf_numbered_when_certified check ((status = 'draft') = (raaf_no is null))
);

create table raaf_line (
  id                  uuid primary key default gen_random_uuid(),
  raaf_id             uuid not null references raaf(id) on delete cascade,
  line_no             int not null check (line_no > 0),
  section             text not null check (section in ('A', 'B')),
  form_type           accountable_form_type not null,
  form_name           text not null,
  series              text,
  accountable_form_id uuid not null references accountable_form(id),
  beg_qty int not null, beg_from bigint, beg_to bigint,
  rec_qty int not null, rec_from bigint, rec_to bigint,
  iss_qty int not null, iss_from bigint, iss_to bigint,
  end_qty int not null, end_from bigint, end_to bigint,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (raaf_id, line_no),
  constraint raaf_line_balances check (beg_qty + rec_qty - iss_qty = end_qty)
);

do $$
declare t text;
begin
  foreach t in array array['raaf', 'raaf_line']
  loop
    execute format('create trigger %I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
    execute format('create trigger %I_audit after insert or update or delete on %I for each row execute function write_audit_log()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- The lines, computed from the booklets and the serials used
-- ---------------------------------------------------------------------------

-- A serial counts as issued on the date of its OR (cancelled ORs included:
-- the form was used) or its check. Serials leave a booklet in order, so the
-- unused stock of a booklet at any date is one unbroken range.
create or replace function raaf_compute(p_barangay uuid, p_year int, p_month int)
returns table (
  line_no int, section text, form_type accountable_form_type, form_name text, series text, accountable_form_id uuid,
  beg_qty int, beg_from bigint, beg_to bigint,
  rec_qty int, rec_from bigint, rec_to bigint,
  iss_qty int, iss_from bigint, iss_to bigint,
  end_qty int, end_from bigint, end_to bigint)
language sql stable as $$
  with bounds as (
    select make_date(p_year, p_month, 1) as d_from,
           (make_date(p_year, p_month, 1) + interval '1 month')::date as d_to
  ),
  used as (
    select o.accountable_form_id as form_id, o.serial_no as serial, o.or_date as used_on
    from official_receipt o where o.barangay_id = p_barangay
    union all
    select c.accountable_form_id, c.check_no, c.check_date
    from bank_check c where c.barangay_id = p_barangay
  ),
  booklets as (
    select f.id, f.form_type, f.form_name, f.series, f.serial_from, f.serial_to, f.next_serial,
           coalesce(f.received_on, '-infinity'::date) < b.d_from as on_hand_before,
           f.disposed_on is not null and f.disposed_on < b.d_to as disposed_in,
           (select max(u.serial) from used u where u.form_id = f.id and u.used_on < b.d_from)  as max_before,
           (select min(u.serial) from used u where u.form_id = f.id and u.used_on >= b.d_from) as min_after,
           (select count(*)      from used u where u.form_id = f.id and u.used_on >= b.d_from and u.used_on < b.d_to) as cnt_in,
           (select min(u.serial) from used u where u.form_id = f.id and u.used_on >= b.d_from and u.used_on < b.d_to) as min_in,
           (select max(u.serial) from used u where u.form_id = f.id and u.used_on >= b.d_from and u.used_on < b.d_to) as max_in
    from accountable_form f cross join bounds b
    where f.barangay_id = p_barangay
      and coalesce(f.received_on, '-infinity'::date) < b.d_to
      and (f.disposed_on is null or f.disposed_on >= b.d_from)
  ),
  calc as (
    -- first unused serial at the start of the month (or on receipt); a
    -- booklet recorded part-used, with no ORs on file, starts at next_serial
    select k.*, coalesce(k.max_before + 1, k.min_after, k.next_serial) as start_from
    from booklets k
  ),
  qty as (
    select c.*,
           greatest(c.serial_to - c.start_from + 1, 0)::int as avail,
           coalesce(c.max_in + 1, c.start_from) as rest_from
    from calc c
  ),
  q as (
    select x.*,
           case when x.on_hand_before then x.avail else 0 end as b_qty,
           case when x.on_hand_before then 0 else x.avail end as r_qty,
           x.cnt_in::int + case when x.disposed_in then greatest(x.serial_to - x.rest_from + 1, 0)::int else 0 end as i_qty
    from qty x
  )
  select (row_number() over (order by case q.form_type when 'cash_ticket' then 0 when 'official_receipt' then 1 else 2 end,
                                      q.serial_from))::int,
         case when q.form_type = 'cash_ticket' then 'A' else 'B' end,
         q.form_type, q.form_name, q.series, q.id,
         q.b_qty, case when q.b_qty > 0 then q.start_from end, case when q.b_qty > 0 then q.serial_to end,
         q.r_qty, case when q.r_qty > 0 then q.start_from end, case when q.r_qty > 0 then q.serial_to end,
         q.i_qty, case when q.i_qty > 0 then coalesce(q.min_in, q.rest_from) end,
                  case when q.i_qty > 0 then case when q.disposed_in then q.serial_to else q.max_in end end,
         q.b_qty + q.r_qty - q.i_qty,
         case when q.b_qty + q.r_qty - q.i_qty > 0 then q.rest_from end,
         case when q.b_qty + q.r_qty - q.i_qty > 0 then q.serial_to end
  from q
  where q.b_qty + q.r_qty + q.i_qty > 0
$$;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

create or replace function raaf_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'RAAF % is certified and cannot be deleted', old.raaf_no using errcode = 'P0001';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.raaf_no is not null then
      raise exception 'a RAAF starts as a draft; use prepare_raaf()' using errcode = 'P0001';
    end if;
    return new;
  end if;
  if current_setting('app.certifying_raaf', true) = old.id::text then
    return new;
  end if;
  if old.status <> 'draft' or new.status <> 'draft' then
    raise exception 'RAAF % is certified with certify_raaf() and is then final', coalesce(old.raaf_no, '(draft)') using errcode = 'P0001';
  end if;
  if (new.barangay_id, new.lgu_id, new.period_year, new.period_month)
     is distinct from (old.barangay_id, old.lgu_id, old.period_year, old.period_month) then
    raise exception 'a draft RAAF keeps its barangay and month; delete it and prepare another' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger raaf_guard before insert or update or delete on raaf
  for each row execute function raaf_guard();

create or replace function raaf_line_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' and current_setting('app.certifying_raaf', true) = new.raaf_id::text then
    return new;
  end if;
  raise exception 'RAAF lines are stored when the report is certified and cannot be changed' using errcode = 'P0001';
end $$;

create trigger raaf_line_guard before insert or update or delete on raaf_line
  for each row execute function raaf_line_guard();

-- ---------------------------------------------------------------------------
-- Prepare and certify
-- ---------------------------------------------------------------------------

create or replace function prepare_raaf(p_barangay uuid, p_year int, p_month int) returns raaf
language plpgsql as $$
declare
  v_lgu  uuid;
  v_raaf raaf;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'barangay not found or not accessible';
  end if;
  if p_month not between 1 and 12 or make_date(p_year, p_month, 1) > manila_today() then
    raise exception 'the month %-% has not started', p_year, lpad(p_month::text, 2, '0');
  end if;
  if exists (select 1 from raaf where barangay_id = p_barangay and period_year = p_year and period_month = p_month) then
    raise exception 'there is already a RAAF for %-%', p_year, lpad(p_month::text, 2, '0');
  end if;
  insert into raaf (lgu_id, barangay_id, period_year, period_month, treasurer_official_id)
  values (v_lgu, p_barangay, p_year, p_month, (barangay_official(p_barangay, 'Barangay Treasurer')).id)
  returning * into v_raaf;
  return v_raaf;
end $$;

create or replace function certify_raaf(p_raaf uuid) returns raaf
language plpgsql as $$
declare
  v_raaf raaf;
  v_end  date;
  v_n    int;
begin
  select * into v_raaf from raaf where id = p_raaf for update;
  if v_raaf.id is null then
    raise exception 'RAAF not found or not accessible';
  end if;
  if v_raaf.status <> 'draft' then
    return v_raaf;
  end if;
  if not has_barangay_role(v_raaf.barangay_id, 'barangay_treasurer') then
    raise exception 'the RAAF is certified by the Barangay Treasurer' using errcode = '42501';
  end if;
  v_end := (make_date(v_raaf.period_year, v_raaf.period_month, 1) + interval '1 month - 1 day')::date;
  if manila_today() < v_end then
    raise exception 'the RAAF for %-% can be certified from the last day of the month (%)',
      v_raaf.period_year, lpad(v_raaf.period_month::text, 2, '0'), v_end;
  end if;

  perform set_config('app.certifying_raaf', p_raaf::text, true);
  insert into raaf_line (raaf_id, line_no, section, form_type, form_name, series, accountable_form_id,
                         beg_qty, beg_from, beg_to, rec_qty, rec_from, rec_to,
                         iss_qty, iss_from, iss_to, end_qty, end_from, end_to)
  select p_raaf, c.line_no, c.section, c.form_type, c.form_name, c.series, c.accountable_form_id,
         c.beg_qty, c.beg_from, c.beg_to, c.rec_qty, c.rec_from, c.rec_to,
         c.iss_qty, c.iss_from, c.iss_to, c.end_qty, c.end_from, c.end_to
  from raaf_compute(v_raaf.barangay_id, v_raaf.period_year, v_raaf.period_month) c;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'no accountable forms on record for %-%', v_raaf.period_year, lpad(v_raaf.period_month::text, 2, '0');
  end if;

  update raaf
  set status = 'certified', certified_at = now(), certified_by = auth.uid(),
      raaf_no = next_document_number(barangay_id, 'RAAF', v_end),
      treasurer_official_id = coalesce(treasurer_official_id, (barangay_official(barangay_id, 'Barangay Treasurer')).id)
  where id = p_raaf
  returning * into v_raaf;
  perform set_config('app.certifying_raaf', '', true);
  return v_raaf;
end $$;

-- ---------------------------------------------------------------------------
-- Row-level security and grants
-- ---------------------------------------------------------------------------

alter table raaf enable row level security;
create policy raaf_select on raaf for select to authenticated using (can_read(lgu_id, barangay_id));
create policy raaf_insert on raaf for insert to authenticated with check (can_write(lgu_id, barangay_id));
create policy raaf_update on raaf for update to authenticated using (can_write(lgu_id, barangay_id)) with check (can_write(lgu_id, barangay_id));
create policy raaf_delete on raaf for delete to authenticated using (can_write(lgu_id, barangay_id));

alter table raaf_line enable row level security;
create policy raaf_line_select on raaf_line for select to authenticated
  using (exists (select 1 from raaf r where r.id = raaf_line.raaf_id and can_read(r.lgu_id, r.barangay_id)));
create policy raaf_line_write on raaf_line for all to authenticated
  using (exists (select 1 from raaf r where r.id = raaf_line.raaf_id and can_write(r.lgu_id, r.barangay_id)))
  with check (exists (select 1 from raaf r where r.id = raaf_line.raaf_id and can_write(r.lgu_id, r.barangay_id)));

grant select, insert, update, delete on raaf, raaf_line to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;
revoke all on all functions in schema public from anon;
