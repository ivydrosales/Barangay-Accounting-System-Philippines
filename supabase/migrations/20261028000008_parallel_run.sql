-- Phase 1, migration 8: the Phase 1 gate check (docs/PROPOSAL.md section 10:
-- "one calendar month run in parallel with paper; totals match").
--
--   For each month of the pilot the Treasurer types in the totals from the
--   paper Cashbook (Annex 8); parallel_run_comparison() sets them beside the
--   same totals worked out by the system, with the difference. When every
--   difference is zero or explained, the C/M Accountant signs the month off;
--   the paper figures are then frozen.
--
--   Only the Cash in Local Treasury and Cash in Bank sections are compared:
--   cash advances and petty cash arrive in Phase 3. Until opening balances
--   are loaded (Phase 2) the system starts from zero, so a difference in the
--   beginning balance carries into the ending balance.

create table parallel_run_month (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  period_year           int not null,
  period_month          int not null check (period_month between 1 and 12),
  -- totals copied from the paper Cashbook and the paper booklets
  paper_clt_beginning   numeric(14,2),
  paper_clt_collection  numeric(14,2),
  paper_clt_deposit     numeric(14,2),
  paper_clt_ending      numeric(14,2),
  paper_cib_beginning   numeric(14,2),
  paper_cib_deposit     numeric(14,2),
  paper_cib_check       numeric(14,2),
  paper_cib_ending      numeric(14,2),
  paper_or_count        int check (paper_or_count >= 0),
  paper_check_count     int check (paper_check_count >= 0),
  notes                 text,
  -- the Accountant's sign-off
  signed_off_at         timestamptz,
  signed_off_by         uuid,
  signoff_remarks       text,
  created_by            uuid default auth.uid(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, period_year, period_month)
);

create trigger parallel_run_month_updated_at before update on parallel_run_month
  for each row execute function set_updated_at();
create trigger parallel_run_month_audit after insert or update or delete on parallel_run_month
  for each row execute function write_audit_log();

create or replace function parallel_run_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.signed_off_at is not null then
      raise exception 'the parallel-run month %-% is signed off and cannot be deleted', old.period_year, lpad(old.period_month::text, 2, '0') using errcode = 'P0001';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and current_setting('app.signing_off', true) = old.id::text then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.signed_off_at is not null then
    raise exception 'the parallel-run month %-% is signed off; its figures are final', old.period_year, lpad(old.period_month::text, 2, '0') using errcode = 'P0001';
  end if;
  if new.signed_off_at is not null or new.signed_off_by is not null or new.signoff_remarks is not null then
    raise exception 'the Accountant signs off with sign_off_parallel_run()' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' and (new.barangay_id, new.lgu_id, new.period_year, new.period_month)
                          is distinct from (old.barangay_id, old.lgu_id, old.period_year, old.period_month) then
    raise exception 'a parallel-run month keeps its barangay and month' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger parallel_run_guard before insert or update or delete on parallel_run_month
  for each row execute function parallel_run_guard();

-- Paper beside system, one row per figure, in the order of the Cashbook.
create or replace function parallel_run_comparison(p_barangay uuid, p_year int, p_month int)
returns table (line_no int, section text, figure text, paper numeric, system numeric, difference numeric)
language sql stable as $$
  with bounds as (
    select make_date(p_year, p_month, 1) as d_from, (make_date(p_year, p_month, 1) + interval '1 month')::date as d_to
  ),
  cb as (
    select * from cashbook(p_barangay, p_year, p_month)
  ),
  sys as (
    select (select clt_balance from cb where seq = 0) as clt_beginning,
           coalesce((select sum(clt_collection) from cb where seq > 0), 0) as clt_collection,
           coalesce((select sum(clt_deposit) from cb where seq > 0), 0) as clt_deposit,
           (select clt_balance from cb order by seq desc limit 1) as clt_ending,
           (select cib_balance from cb where seq = 0) as cib_beginning,
           coalesce((select sum(cib_deposit) from cb where seq > 0), 0) as cib_deposit,
           coalesce((select sum(cib_check) from cb where seq > 0), 0) as cib_check,
           (select cib_balance from cb order by seq desc limit 1) as cib_ending,
           (select count(*) from official_receipt o, bounds b
             where o.barangay_id = p_barangay and o.or_date >= b.d_from and o.or_date < b.d_to) as or_count,
           (select count(*) from bank_check c, bounds b
             where c.barangay_id = p_barangay and c.check_date >= b.d_from and c.check_date < b.d_to) as check_count
  ),
  paper as (
    select * from parallel_run_month
    where barangay_id = p_barangay and period_year = p_year and period_month = p_month
  ),
  rows as (
    select v.*
    from sys s left join paper p on true,
    lateral (values
      (1,  'Cash in Local Treasury', 'Beginning balance',           p.paper_clt_beginning,  s.clt_beginning),
      (2,  'Cash in Local Treasury', 'Collections',                 p.paper_clt_collection, s.clt_collection),
      (3,  'Cash in Local Treasury', 'Deposits',                    p.paper_clt_deposit,    s.clt_deposit),
      (4,  'Cash in Local Treasury', 'Ending balance',              p.paper_clt_ending,     s.clt_ending),
      (5,  'Cash in Bank',           'Beginning balance',           p.paper_cib_beginning,  s.cib_beginning),
      (6,  'Cash in Bank',           'Deposits',                    p.paper_cib_deposit,    s.cib_deposit),
      (7,  'Cash in Bank',           'Checks issued',               p.paper_cib_check,      s.cib_check),
      (8,  'Cash in Bank',           'Ending balance',              p.paper_cib_ending,     s.cib_ending),
      (9,  'Accountable forms',      'Official Receipts used (count, cancelled included)', p.paper_or_count::numeric, s.or_count::numeric),
      (10, 'Accountable forms',      'Checks issued (count)',       p.paper_check_count::numeric, s.check_count::numeric)
    ) as v(line_no, section, figure, paper, system)
  )
  select line_no, section, figure, paper, system, system - paper
  from rows
  order by line_no
$$;

create or replace function sign_off_parallel_run(p_id uuid, p_remarks text default null) returns parallel_run_month
language plpgsql as $$
declare
  v_row  parallel_run_month;
  v_open int;
begin
  select * into v_row from parallel_run_month where id = p_id for update;
  if v_row.id is null then
    raise exception 'parallel-run month not found or not accessible';
  end if;
  if not is_lgu_staff(v_row.lgu_id) then
    raise exception 'the C/M Accountant''s office signs off the parallel run' using errcode = '42501';
  end if;
  if v_row.signed_off_at is not null then
    return v_row;
  end if;
  if (make_date(v_row.period_year, v_row.period_month, 1) + interval '1 month')::date > manila_today() then
    raise exception 'the month %-% is not over yet', v_row.period_year, lpad(v_row.period_month::text, 2, '0');
  end if;
  select count(*) into v_open
  from parallel_run_comparison(v_row.barangay_id, v_row.period_year, v_row.period_month)
  where paper is null;
  if v_open > 0 then
    raise exception '% paper figure(s) are still blank; type them in before signing off', v_open;
  end if;
  select count(*) into v_open
  from parallel_run_comparison(v_row.barangay_id, v_row.period_year, v_row.period_month)
  where difference <> 0;
  if v_open > 0 and coalesce(trim(p_remarks), '') = '' then
    raise exception '% figure(s) differ; explain them in the remarks to sign off', v_open;
  end if;

  perform set_config('app.signing_off', p_id::text, true);
  update parallel_run_month
  set signed_off_at = now(), signed_off_by = auth.uid(), signoff_remarks = nullif(trim(p_remarks), '')
  where id = p_id
  returning * into v_row;
  perform set_config('app.signing_off', '', true);
  return v_row;
end $$;

alter table parallel_run_month enable row level security;
create policy parallel_run_month_select on parallel_run_month for select to authenticated using (can_read(lgu_id, barangay_id));
create policy parallel_run_month_insert on parallel_run_month for insert to authenticated with check (can_write(lgu_id, barangay_id));
create policy parallel_run_month_update on parallel_run_month for update to authenticated using (can_write(lgu_id, barangay_id)) with check (can_write(lgu_id, barangay_id));
create policy parallel_run_month_delete on parallel_run_month for delete to authenticated using (can_write(lgu_id, barangay_id));

grant select, insert, update, delete on parallel_run_month to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;
revoke all on all functions in schema public from anon;
