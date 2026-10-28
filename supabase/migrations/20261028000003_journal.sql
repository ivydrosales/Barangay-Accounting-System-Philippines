-- Phase 0, migration 3: accounting periods, document numbering and the
-- journal. One journal-entry table (header + lines) with a book flag
-- (JCT or GJ); ledgers are queries over it. Balances are never stored.
--
-- Rules enforced here, from the manual (section refs in docs/PROPOSAL.md):
--   * postings balance (1.2.2) and use only chart accounts (1.2.3)
--   * cash entries go to the JCT, non-cash to the GJ (1.2.5)
--   * document numbers are YYYY-MM-serial, one series per year, no gaps
--   * posted entries are never edited; corrections are reversing entries
--   * closed periods are immutable

-- ---------------------------------------------------------------------------
-- Periods: one row per barangay per month. Fiscal year = calendar year.
-- ---------------------------------------------------------------------------

create table period (
  id           uuid primary key default gen_random_uuid(),
  lgu_id       uuid not null references lgu(id),
  barangay_id  uuid not null references barangay(id),
  fiscal_year  int not null check (fiscal_year between 2000 and 2100),
  month        int not null check (month between 1 and 12),
  status       period_status not null default 'open',
  closed_at    timestamptz,
  closed_by    uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, fiscal_year, month)
);

create trigger period_updated_at before update on period
  for each row execute function set_updated_at();

-- Once closed, a period stays closed. Corrections go through a reversing
-- entry in an open period (CLAUDE.md). Reopening is a product decision for
-- Ivy; until then the database refuses it.
create or replace function period_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'periods cannot be deleted' using errcode = 'P0001';
  end if;
  if old.status = 'closed' and new.status <> 'closed' then
    raise exception 'closed periods are immutable (% %-%)', old.barangay_id, old.fiscal_year, old.month
      using errcode = 'P0001';
  end if;
  if old.status = 'closed' and (new.fiscal_year, new.month, new.barangay_id) is distinct from (old.fiscal_year, old.month, old.barangay_id) then
    raise exception 'closed periods are immutable' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger period_guard before update or delete on period
  for each row execute function period_guard();

-- Finds the period a date falls in, creating it open if it does not exist yet.
create or replace function ensure_period(p_barangay uuid, p_date date) returns period
language plpgsql security definer set search_path = public as $$
declare
  v_lgu uuid;
  v_period period;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'unknown barangay %', p_barangay;
  end if;

  insert into period (lgu_id, barangay_id, fiscal_year, month)
  values (v_lgu, p_barangay, extract(year from p_date)::int, extract(month from p_date)::int)
  on conflict (barangay_id, fiscal_year, month) do nothing;

  select * into v_period from period
  where barangay_id = p_barangay
    and fiscal_year = extract(year from p_date)::int
    and month = extract(month from p_date)::int;
  return v_period;
end $$;

create or replace function is_period_closed(p_barangay uuid, p_date date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from period
    where barangay_id = p_barangay
      and fiscal_year = extract(year from p_date)::int
      and month = extract(month from p_date)::int
      and status = 'closed'
  )
$$;

-- Only the Accountant's office closes a month.
create or replace function close_period(p_barangay uuid, p_year int, p_month int) returns period
language plpgsql security definer set search_path = public as $$
declare
  v_lgu uuid;
  v_period period;
begin
  select lgu_id into v_lgu from barangay where id = p_barangay;
  if v_lgu is null then
    raise exception 'unknown barangay %', p_barangay;
  end if;
  if not is_lgu_staff(v_lgu) then
    raise exception 'only the C/M Accountant''s office can close a period' using errcode = '42501';
  end if;

  v_period := ensure_period(p_barangay, make_date(p_year, p_month, 1));
  if v_period.status = 'closed' then
    return v_period;
  end if;

  update period
  set status = 'closed', closed_at = now(), closed_by = auth.uid()
  where id = v_period.id
  returning * into v_period;
  return v_period;
end $$;

-- ---------------------------------------------------------------------------
-- Document numbers: YYYY-MM-serial, one series per barangay, document type
-- and year (per month when p_monthly, as the SSMI requires). The row lock on
-- the sequence row is what guarantees no duplicates; numbers are only taken
-- at posting time, so abandoned drafts leave no gaps.
-- ---------------------------------------------------------------------------

create table document_sequence (
  lgu_id       uuid not null references lgu(id),
  barangay_id  uuid not null references barangay(id),
  doc_type     text not null,                 -- 'JCT', 'GJ', 'DV', 'OR', 'RCD', 'JV' ...
  fiscal_year  int not null,
  month        int not null default 0,        -- 0 = yearly series
  last_serial  int not null default 0,
  primary key (barangay_id, doc_type, fiscal_year, month)
);

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

  return format('%s-%s-%s', v_year, lpad(v_month::text, 2, '0'), lpad(v_serial::text, 4, '0'));
end $$;

-- ---------------------------------------------------------------------------
-- Journal entries
-- ---------------------------------------------------------------------------

create table journal_entry (
  id                 uuid primary key default gen_random_uuid(),
  lgu_id             uuid not null references lgu(id),
  barangay_id        uuid not null references barangay(id),
  fund_id            uuid not null references fund(id),
  book               journal_book not null,
  entry_no           text,                                -- assigned on posting
  entry_date         date not null,
  period_id          uuid references period(id),          -- set on posting
  description        text not null,
  source_type        text,                                -- the document behind it: RCD, DV, JV, LR ...
  source_id          uuid,
  status             entry_status not null default 'draft',
  posted_at          timestamptz,
  posted_by          uuid,
  reverses_entry_id  uuid references journal_entry(id),   -- set on the reversing entry
  reversed_by_id     uuid references journal_entry(id),   -- set on the original
  created_by         uuid default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  foreign key (fund_id, barangay_id) references fund(id, barangay_id),
  unique (barangay_id, book, entry_no),
  constraint posted_fields check (
    (status = 'draft' and entry_no is null and posted_at is null)
    or (status <> 'draft' and entry_no is not null and posted_at is not null and period_id is not null)
  )
);

create index on journal_entry (barangay_id, entry_date);
create index on journal_entry (source_type, source_id);

create table journal_line (
  id               uuid primary key default gen_random_uuid(),
  entry_id         uuid not null references journal_entry(id) on delete cascade,
  line_no          int not null check (line_no > 0),
  account_code     text not null references account(code),
  debit            numeric(14,2) not null default 0 check (debit >= 0),
  credit           numeric(14,2) not null default 0 check (credit >= 0),
  -- Subsidiary-ledger key (per creditor, per employee, per property item ...)
  subsidiary_type  text,
  subsidiary_id    uuid,
  subsidiary_label text,
  particulars      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (entry_id, line_no),
  constraint one_side_only check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create index on journal_line (account_code);
create index on journal_line (subsidiary_type, subsidiary_id);

create trigger journal_entry_updated_at before update on journal_entry
  for each row execute function set_updated_at();
create trigger journal_line_updated_at before update on journal_line
  for each row execute function set_updated_at();

-- Header guard: no changes to posted entries, nothing in closed periods, and
-- the draft -> posted transition only through post_journal_entry().
create or replace function journal_entry_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'posted entry % cannot be deleted; reverse it instead', old.entry_no using errcode = 'P0001';
    end if;
    if is_period_closed(old.barangay_id, old.entry_date) then
      raise exception 'period is closed for %', old.entry_date using errcode = 'P0001';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    -- Marking a posted entry as reversed only links it to its reversing entry;
    -- the books of its period do not change, so this is allowed even after the
    -- period closes. reverse_journal_entry() sets the flag.
    if old.status = 'posted' and new.status = 'reversed'
       and current_setting('app.reversing_entry', true) = old.id::text
       and (new.lgu_id, new.barangay_id, new.fund_id, new.book, new.entry_no, new.entry_date, new.period_id,
            new.description, new.source_type, new.source_id, new.posted_at, new.posted_by, new.reverses_entry_id)
           is not distinct from
           (old.lgu_id, old.barangay_id, old.fund_id, old.book, old.entry_no, old.entry_date, old.period_id,
            old.description, old.source_type, old.source_id, old.posted_at, old.posted_by, old.reverses_entry_id)
    then
      return new;
    end if;

    if old.status <> 'draft' then
      raise exception 'posted entry % is immutable; reverse it with reverse_journal_entry()', old.entry_no
        using errcode = 'P0001';
    end if;
  end if;

  if is_period_closed(new.barangay_id, new.entry_date) then
    raise exception 'period is closed for %', new.entry_date using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'entries are created as drafts and posted with post_journal_entry()' using errcode = 'P0001';
    end if;
    return new;
  end if;

  -- UPDATE of a draft
  if new.status = 'posted' and current_setting('app.posting_entry', true) is distinct from new.id::text then
    raise exception 'use post_journal_entry() to post' using errcode = 'P0001';
  end if;
  if new.status = 'reversed' then
    raise exception 'a draft cannot be reversed; delete it' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger journal_entry_guard before insert or update or delete on journal_entry
  for each row execute function journal_entry_guard();

-- Line guard: lines change only while the entry is a draft, and only with
-- active chart accounts.
create or replace function journal_line_guard() returns trigger
language plpgsql as $$
declare
  v_entry journal_entry;
  v_active boolean;
begin
  select * into v_entry from journal_entry where id = coalesce(new.entry_id, old.entry_id);
  if v_entry.id is null then
    -- parent is being deleted (cascade); allow
    return coalesce(new, old);
  end if;
  if v_entry.status <> 'draft' then
    raise exception 'entry % is posted; its lines are immutable', v_entry.entry_no using errcode = 'P0001';
  end if;
  if tg_op <> 'DELETE' then
    select is_active into v_active from account where code = new.account_code;
    if not coalesce(v_active, false) then
      raise exception 'account % is not an active chart account', new.account_code using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end $$;

create trigger journal_line_guard before insert or update or delete on journal_line
  for each row execute function journal_line_guard();

-- ---------------------------------------------------------------------------
-- Posting: balance check, period, number, status. Runs as the caller, so RLS
-- decides whether they may touch this barangay's entries.
-- ---------------------------------------------------------------------------

create or replace function post_journal_entry(p_entry uuid) returns journal_entry
language plpgsql as $$
declare
  v_entry   journal_entry;
  v_debits  numeric(14,2);
  v_credits numeric(14,2);
  v_lines   int;
  v_period  period;
begin
  select * into v_entry from journal_entry where id = p_entry for update;
  if v_entry.id is null then
    raise exception 'entry % not found or not accessible', p_entry;
  end if;
  if v_entry.status <> 'draft' then
    raise exception 'entry % is already %', v_entry.entry_no, v_entry.status;
  end if;

  select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_lines, v_debits, v_credits
  from journal_line where entry_id = p_entry;

  if v_lines < 2 then
    raise exception 'an entry needs at least one debit and one credit line';
  end if;
  if v_debits <> v_credits then
    raise exception 'entry does not balance: debits % vs credits %', v_debits, v_credits;
  end if;
  if v_debits = 0 then
    raise exception 'entry has no amount';
  end if;

  v_period := ensure_period(v_entry.barangay_id, v_entry.entry_date);
  if v_period.status = 'closed' then
    raise exception 'period %-% is closed', v_period.fiscal_year, v_period.month;
  end if;

  perform set_config('app.posting_entry', p_entry::text, true);
  update journal_entry
  set status    = 'posted',
      entry_no  = next_document_number(v_entry.barangay_id, v_entry.book::text, v_entry.entry_date),
      period_id = v_period.id,
      posted_at = now(),
      posted_by = auth.uid()
  where id = p_entry
  returning * into v_entry;
  perform set_config('app.posting_entry', '', true);

  return v_entry;
end $$;

-- Reversal: a new GJ entry with debits and credits swapped, posted at once;
-- the original is marked reversed and the two point at each other.
create or replace function reverse_journal_entry(p_entry uuid, p_date date, p_reason text) returns journal_entry
language plpgsql as $$
declare
  v_orig journal_entry;
  v_rev  journal_entry;
begin
  select * into v_orig from journal_entry where id = p_entry for update;
  if v_orig.id is null then
    raise exception 'entry % not found or not accessible', p_entry;
  end if;
  if v_orig.status <> 'posted' then
    raise exception 'only posted entries can be reversed';
  end if;
  if p_date < v_orig.entry_date then
    raise exception 'a reversal cannot be dated before the entry it reverses';
  end if;

  insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description,
                             source_type, source_id, reverses_entry_id)
  values (v_orig.lgu_id, v_orig.barangay_id, v_orig.fund_id, 'GJ', p_date,
          format('Reversal of %s %s: %s', v_orig.book, v_orig.entry_no, p_reason),
          'REVERSAL', v_orig.id, v_orig.id)
  returning * into v_rev;

  insert into journal_line (entry_id, line_no, account_code, debit, credit,
                            subsidiary_type, subsidiary_id, subsidiary_label, particulars)
  select v_rev.id, line_no, account_code, credit, debit,
         subsidiary_type, subsidiary_id, subsidiary_label, particulars
  from journal_line where entry_id = v_orig.id;

  v_rev := post_journal_entry(v_rev.id);

  perform set_config('app.reversing_entry', v_orig.id::text, true);
  update journal_entry set status = 'reversed', reversed_by_id = v_rev.id where id = v_orig.id;
  perform set_config('app.reversing_entry', '', true);

  return v_rev;
end $$;

-- ---------------------------------------------------------------------------
-- Ledgers are views over posted lines. GL per account; SL per subsidiary key.
-- ---------------------------------------------------------------------------

create or replace view general_ledger as
select e.lgu_id, e.barangay_id, e.fund_id, e.book, e.entry_no, e.entry_date, e.period_id,
       l.account_code, a.title as account_title, a.normal_balance,
       l.debit, l.credit, l.particulars, e.description, e.id as entry_id, l.id as line_id
from journal_line l
join journal_entry e on e.id = l.entry_id
join account a on a.code = l.account_code
where e.status in ('posted', 'reversed');

create or replace view subsidiary_ledger as
select * from general_ledger
where exists (
  select 1 from journal_line l where l.id = general_ledger.line_id and l.subsidiary_id is not null
);

create or replace view trial_balance as
select e.lgu_id, e.barangay_id, e.fund_id, p.fiscal_year, p.month,
       l.account_code, a.title as account_title, a.class, a.normal_balance,
       sum(l.debit)  as total_debit,
       sum(l.credit) as total_credit,
       case a.normal_balance
         when 'Dr' then sum(l.debit) - sum(l.credit)
         else sum(l.credit) - sum(l.debit)
       end as balance
from journal_line l
join journal_entry e on e.id = l.entry_id
join period p on p.id = e.period_id
join account a on a.code = l.account_code
where e.status in ('posted', 'reversed')
group by e.lgu_id, e.barangay_id, e.fund_id, p.fiscal_year, p.month,
         l.account_code, a.title, a.class, a.normal_balance;
