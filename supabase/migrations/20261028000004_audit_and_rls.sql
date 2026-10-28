-- Phase 0, migration 4: the audit trail and row-level security.
--
-- COA will ask who changed a record and when, so every insert, update and
-- delete on every business table is copied into audit_log. Then RLS: a
-- barangay user sees only their barangay, the Accountant's office sees the
-- whole LGU, COA auditors read everything and write nothing.

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

create table audit_log (
  id          bigint generated always as identity primary key,
  lgu_id      uuid,
  barangay_id uuid,
  table_name  text not null,
  row_id      text not null,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data    jsonb,
  new_data    jsonb,
  changed_by  uuid,
  changed_at  timestamptz not null default now()
);

create index on audit_log (table_name, row_id);
create index on audit_log (barangay_id, changed_at);

create or replace function audit_log_guard() returns trigger
language plpgsql as $$
begin
  raise exception 'audit_log is append-only' using errcode = 'P0001';
end $$;

create trigger audit_log_guard before update or delete on audit_log
  for each row execute function audit_log_guard();

create or replace function write_audit_log() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_row      jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_lgu      uuid  := (v_row ->> 'lgu_id')::uuid;
  v_barangay uuid  := (v_row ->> 'barangay_id')::uuid;
begin
  if tg_table_name = 'lgu' then
    v_lgu := (v_row ->> 'id')::uuid;
  end if;
  -- journal lines carry no tenant columns of their own; take the header's
  if tg_table_name = 'journal_line' then
    select e.lgu_id, e.barangay_id into v_lgu, v_barangay
    from journal_entry e where e.id = (v_row ->> 'entry_id')::uuid;
  end if;

  insert into audit_log (lgu_id, barangay_id, table_name, row_id, action, old_data, new_data, changed_by)
  values (
    v_lgu, v_barangay, tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'code', v_row::text),
    tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end,
    auth.uid()
  );
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'lgu', 'barangay', 'user_membership', 'account', 'official', 'fund', 'bank_account',
    'supplier', 'employee', 'accountable_form', 'period', 'journal_entry', 'journal_line'
  ]
  loop
    execute format(
      'create trigger %I_audit after insert or update or delete on %I for each row execute function write_audit_log()',
      t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

-- Tables with lgu_id and barangay_id (barangay_id may be null = LGU-wide row)
do $$
declare t text;
begin
  foreach t in array array[
    'official', 'fund', 'bank_account', 'employee', 'accountable_form',
    'period', 'journal_entry', 'audit_log'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I_select on %I for select to authenticated using (can_read(lgu_id, barangay_id))', t, t);
  end loop;

  -- writable by the people who cover the row; period and audit_log excepted
  foreach t in array array['official', 'fund', 'bank_account', 'employee', 'accountable_form', 'journal_entry']
  loop
    execute format('create policy %I_insert on %I for insert to authenticated with check (can_write(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_update on %I for update to authenticated using (can_write(lgu_id, barangay_id)) with check (can_write(lgu_id, barangay_id))', t, t);
    execute format('create policy %I_delete on %I for delete to authenticated using (can_write(lgu_id, barangay_id))', t, t);
  end loop;
end $$;

-- barangay rows: visible to whoever covers them, created by LGU staff only
alter table barangay enable row level security;
create policy barangay_select on barangay for select to authenticated using (has_barangay_access(id));
create policy barangay_write on barangay for all to authenticated
  using (is_lgu_staff(lgu_id)) with check (is_lgu_staff(lgu_id));

-- LGU-wide tables
alter table lgu enable row level security;
create policy lgu_select on lgu for select to authenticated using (has_lgu_access(id));
create policy lgu_update on lgu for update to authenticated using (is_lgu_staff(id)) with check (is_lgu_staff(id));

alter table supplier enable row level security;
create policy supplier_select on supplier for select to authenticated using (has_lgu_access(lgu_id));
create policy supplier_write on supplier for all to authenticated
  using (can_write(lgu_id, null)) with check (can_write(lgu_id, null));

-- Memberships: you can see your own and those of LGUs you administer;
-- only LGU admins grant access.
alter table user_membership enable row level security;
create policy membership_select on user_membership for select to authenticated
  using (user_id = auth.uid() or is_lgu_staff(lgu_id));
create policy membership_admin on user_membership for all to authenticated
  using (is_lgu_admin(lgu_id)) with check (is_lgu_admin(lgu_id));

-- Chart of accounts: everyone reads, nobody edits from the app
alter table account enable row level security;
create policy account_select on account for select to authenticated using (true);

-- Journal lines follow their header
alter table journal_line enable row level security;
create policy journal_line_select on journal_line for select to authenticated
  using (exists (select 1 from journal_entry e where e.id = journal_line.entry_id and can_read(e.lgu_id, e.barangay_id)));
create policy journal_line_write on journal_line for all to authenticated
  using (exists (select 1 from journal_entry e where e.id = journal_line.entry_id and can_write(e.lgu_id, e.barangay_id)))
  with check (exists (select 1 from journal_entry e where e.id = journal_line.entry_id and can_write(e.lgu_id, e.barangay_id)));

-- Periods are created by ensure_period() and closed by close_period(); the
-- only direct change allowed is none.
-- Document sequences are read-only to users; next_document_number() writes.
alter table document_sequence enable row level security;
create policy document_sequence_select on document_sequence for select to authenticated
  using (can_read(lgu_id, barangay_id));

-- Views run with the invoker's rights so RLS on the base tables applies.
alter view general_ledger set (security_invoker = true);
alter view subsidiary_ledger set (security_invoker = true);
alter view trial_balance set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- Grants. Supabase sets these as defaults; we state them so a plain Postgres
-- (the test database) behaves the same. anon gets nothing.
-- ---------------------------------------------------------------------------

grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;

-- direct writes to the sequence table and audit log stay with the functions
revoke insert, update, delete on document_sequence from authenticated;
revoke insert, update, delete on audit_log from authenticated;
revoke insert, update, delete on account from authenticated;
revoke insert, update, delete on period from authenticated;
