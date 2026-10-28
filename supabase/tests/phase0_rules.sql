-- Phase 0 rule tests: the database must enforce these on its own, whatever
-- the app does. Run with scripts/db-test.sh. Everything here is rolled back.
--
-- Each check prints "ok: ..." as a NOTICE; the first failure stops the run
-- with "FAIL: ...".

\set ON_ERROR_STOP on
begin;

create function pg_temp.assert(p_ok boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not coalesce(p_ok, false) then
    raise exception 'FAIL: %', p_msg;
  end if;
  raise notice 'ok: %', p_msg;
end $$;

create function pg_temp.expect_error(p_sql text, p_msg text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL: % (no error raised)', p_msg;
exception
  when others then
    if sqlerrm like 'FAIL:%' then
      raise;
    end if;
    raise notice 'ok: % -> %', p_msg, sqlerrm;
end $$;

-- Pretend to be a logged-in Supabase user.
create function pg_temp.login(p_user uuid) returns void
language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true)
$$;

-- ---------------------------------------------------------------------------
-- Fixtures: LGU X (barangays A and B), LGU Y (barangay C), five logins
-- ---------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'treasurer-a@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'accountant-x@test.local'),
  ('00000000-0000-0000-0000-000000000003', 'auditor-x@test.local'),
  ('00000000-0000-0000-0000-000000000004', 'treasurer-b@test.local'),
  ('00000000-0000-0000-0000-000000000005', 'accountant-y@test.local');

insert into lgu (id, name, lgu_type, province) values
  ('10000000-0000-0000-0000-000000000001', 'Test City', 'city', 'Test Province'),
  ('10000000-0000-0000-0000-000000000002', 'Other Town', 'municipality', 'Test Province');

insert into barangay (id, lgu_id, name) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Barangay A'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Barangay B'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'Barangay C');

insert into user_membership (user_id, lgu_id, barangay_id, role) values
  ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'barangay_treasurer'),
  ('00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', null, 'lgu_accountant'),
  ('00000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', null, 'coa_auditor'),
  ('00000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'barangay_treasurer'),
  ('00000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000002', null, 'lgu_accountant');

select set_config('test.fund_b', (select id::text from fund where barangay_id = '20000000-0000-0000-0000-000000000002' and code = 'GF'), true);
select set_config('test.revenue', (select min(code) from account where class = 'Revenue'), true);

-- ---------------------------------------------------------------------------
-- Seed and master data
-- ---------------------------------------------------------------------------

select pg_temp.assert((select count(*) from account) = 280, 'chart of accounts has 280 accounts');
select pg_temp.assert(
  not exists (select 1 from account c join account p on p.code = c.contra_of where c.normal_balance = p.normal_balance),
  'every contra account carries the opposite normal balance of its parent');
select pg_temp.assert(
  (select count(*) from fund where barangay_id = '20000000-0000-0000-0000-000000000001') = 5
  and (select string_agg(code, ',' order by code) from fund where barangay_id = '20000000-0000-0000-0000-000000000001') = 'CA,DF,GF,LDRRMF,SK',
  'a new barangay gets the five standard funds');
select pg_temp.expect_error(
  $sql$ insert into fund (lgu_id, barangay_id, fund_type, code, name)
        values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'stf', 'STF-1', 'Trust') $sql$,
  'a special trust fund needs a purpose');
select pg_temp.expect_error(
  $sql$ insert into fund (lgu_id, barangay_id, fund_type, code, name)
        values ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'stf', 'STF-2', 'Trust') $sql$,
  'a fund cannot point at a barangay of another LGU');

-- ---------------------------------------------------------------------------
-- As the Barangay A treasurer
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

select pg_temp.assert((select count(*) from barangay) = 1, 'treasurer sees only their own barangay');
select pg_temp.assert((select count(*) from fund) = 5, 'treasurer sees only their own funds');
select pg_temp.assert((select count(*) from account) = 280, 'treasurer can read the chart of accounts');
select pg_temp.expect_error(
  $sql$ insert into account (code, title, class, account_group, normal_balance) values ('1-99-99-999', 'Made up', 'Asset', 'Cash', 'Dr') $sql$,
  'treasurer cannot add accounts to the chart');

do $$
declare
  v_lgu  uuid := '10000000-0000-0000-0000-000000000001';
  v_b    uuid := '20000000-0000-0000-0000-000000000001';
  v_fund uuid;
  v_rev  text := current_setting('test.revenue');
  v_e1   uuid; v_e2 uuid; v_e3 uuid;
  v_row  journal_entry;
begin
  select id into v_fund from fund where barangay_id = v_b and code = 'GF';

  -- entry 1: unbalanced, then fixed
  insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description)
  values (v_lgu, v_b, v_fund, 'JCT', '2026-01-15', 'Collections per RCD') returning id into v_e1;
  insert into journal_line (entry_id, line_no, account_code, debit)  values (v_e1, 1, '1-01-01-010', 1500);
  insert into journal_line (entry_id, line_no, account_code, credit) values (v_e1, 2, v_rev, 1000);

  perform pg_temp.expect_error(format('select post_journal_entry(%L)', v_e1), 'an unbalanced entry cannot be posted');
  perform pg_temp.expect_error(
    format($q$ update journal_entry set status = 'posted', entry_no = 'X', posted_at = now(), period_id = gen_random_uuid() where id = %L $q$, v_e1),
    'status cannot be flipped to posted by hand');

  update journal_line set credit = 1500 where entry_id = v_e1 and line_no = 2;
  v_row := post_journal_entry(v_e1);
  perform pg_temp.assert(v_row.status = 'posted' and v_row.entry_no = '2026-01-001' and v_row.period_id is not null,
    'a balanced entry posts and receives number 2026-01-001');
  perform pg_temp.assert(
    (select status = 'open' from period where barangay_id = v_b and fiscal_year = 2026 and month = 1),
    'posting opens the period on first use');

  -- posted entries and their lines are frozen
  perform pg_temp.expect_error(format($q$ update journal_entry set description = 'edited' where id = %L $q$, v_e1), 'posted entry header cannot be edited');
  perform pg_temp.expect_error(format($q$ delete from journal_entry where id = %L $q$, v_e1), 'posted entry cannot be deleted');
  perform pg_temp.expect_error(format($q$ update journal_line set debit = 1 where entry_id = %L and line_no = 1 $q$, v_e1), 'posted entry lines cannot be edited');
  perform pg_temp.expect_error(format($q$ delete from journal_line where entry_id = %L $q$, v_e1), 'posted entry lines cannot be deleted');
  perform pg_temp.expect_error(format($q$ insert into journal_line (entry_id, line_no, account_code, debit) values (%L, 3, '1-01-01-010', 1) $q$, v_e1), 'lines cannot be added to a posted entry');
  perform pg_temp.expect_error(format('select post_journal_entry(%L)', v_e1), 'an entry cannot be posted twice');

  -- numbering: one series per book per year, serial continues across months
  insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description)
  values (v_lgu, v_b, v_fund, 'JCT', '2026-01-16', 'Second') returning id into v_e2;
  insert into journal_line (entry_id, line_no, account_code, debit)  values (v_e2, 1, '1-01-01-010', 200);
  insert into journal_line (entry_id, line_no, account_code, credit) values (v_e2, 2, v_rev, 200);
  v_row := post_journal_entry(v_e2);
  perform pg_temp.assert(v_row.entry_no = '2026-01-002', 'second JCT entry is 2026-01-002');

  insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description)
  values (v_lgu, v_b, v_fund, 'JCT', '2026-02-03', 'Third') returning id into v_e3;
  insert into journal_line (entry_id, line_no, account_code, debit)  values (v_e3, 1, '1-01-01-010', 300);
  insert into journal_line (entry_id, line_no, account_code, credit) values (v_e3, 2, v_rev, 300);
  v_row := post_journal_entry(v_e3);
  perform pg_temp.assert(v_row.entry_no = '2026-02-003', 'February entry continues the yearly series as 2026-02-003');

  -- line rules
  perform pg_temp.expect_error(
    format($q$ insert into journal_entry (id, lgu_id, barangay_id, fund_id, book, entry_date, description) values ('30000000-0000-0000-0000-000000000001', %L, %L, %L, 'GJ', '2026-02-05', 'Draft');
               insert into journal_line (entry_id, line_no, account_code, debit) values ('30000000-0000-0000-0000-000000000001', 1, '9-99-99-999', 10) $q$, v_lgu, v_b, v_fund),
    'a line cannot use an account that is not in the chart');
  perform pg_temp.expect_error(
    format($q$ insert into journal_entry (id, lgu_id, barangay_id, fund_id, book, entry_date, description) values ('30000000-0000-0000-0000-000000000002', %L, %L, %L, 'GJ', '2026-02-05', 'Draft');
               insert into journal_line (entry_id, line_no, account_code, debit, credit) values ('30000000-0000-0000-0000-000000000002', 1, '1-01-01-010', 10, 10) $q$, v_lgu, v_b, v_fund),
    'a line is either a debit or a credit, never both');
  perform pg_temp.expect_error(
    format($q$ insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description) values (%L, %L, %L, 'GJ', '2026-02-05', 'Wrong fund') $q$, v_lgu, v_b, current_setting('test.fund_b')),
    'an entry cannot use another barangay''s fund');

  perform set_config('test.e1', v_e1::text, true);
end $$;

-- cannot reach barangay B
select pg_temp.expect_error(
  format($q$ insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description)
             values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', %L, 'JCT', '2026-01-15', 'Not mine') $q$,
         current_setting('test.fund_b')),
  'treasurer cannot write entries for another barangay');
select pg_temp.expect_error(
  $sql$ select close_period('20000000-0000-0000-0000-000000000001', 2026, 1) $sql$,
  'treasurer cannot close a period');
select pg_temp.assert((select count(*) from general_ledger) = 6, 'treasurer sees their 6 ledger lines');

-- ---------------------------------------------------------------------------
-- As the C/M Accountant of LGU X
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000002');

select pg_temp.assert((select count(*) from barangay) = 2, 'accountant sees every barangay of the LGU');
select pg_temp.assert((select count(*) from journal_entry where status = 'posted') = 3, 'accountant sees the barangay''s posted entries');

select pg_temp.assert((select status = 'closed' from close_period('20000000-0000-0000-0000-000000000001', 2026, 1)), 'accountant closes January');
select pg_temp.expect_error(
  $sql$ insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description)
        values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
                (select id from fund where barangay_id = '20000000-0000-0000-0000-000000000001' and code = 'GF'), 'GJ', '2026-01-20', 'Late') $sql$,
  'nothing can be entered in a closed period');
select pg_temp.expect_error(
  $sql$ update period set status = 'open' where barangay_id = '20000000-0000-0000-0000-000000000001' and month = 1 $sql$,
  'a closed period cannot be reopened');

do $$
declare
  v_orig uuid := current_setting('test.e1')::uuid;
  v_rev  journal_entry;
begin
  v_rev := reverse_journal_entry(v_orig, '2026-02-10', 'posted to the wrong fund');
  perform pg_temp.assert(v_rev.book = 'GJ' and v_rev.entry_no = '2026-02-001' and v_rev.status = 'posted' and v_rev.reverses_entry_id = v_orig,
    'reversal is a posted GJ entry with its own series');
  perform pg_temp.assert(
    (select status = 'reversed' and reversed_by_id = v_rev.id from journal_entry where id = v_orig),
    'the original is marked reversed and linked, even though its period is closed');
  perform pg_temp.assert(
    (select sum(credit) = 1500 and sum(debit) = 1500 from journal_line where entry_id = v_rev.id)
    and (select credit = 1500 from journal_line where entry_id = v_rev.id and account_code = '1-01-01-010'),
    'reversal swaps debits and credits');
  perform pg_temp.expect_error(format('select reverse_journal_entry(%L, %L, %L)', v_orig, '2026-02-11', 'again'), 'an entry cannot be reversed twice');
  perform pg_temp.assert(
    (select sum(balance) = 500 from trial_balance where barangay_id = '20000000-0000-0000-0000-000000000001' and account_code = '1-01-01-010'),
    'trial balance nets to 1500 + 200 + 300 - 1500 = 500 for Cash in Local Treasury');
end $$;

-- bank accounts and accountable forms
insert into bank_account (lgu_id, barangay_id, bank_name, account_number, account_name)
values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'LBP', '0001-0001', 'Barangay A');
select pg_temp.expect_error(
  $sql$ insert into bank_account (lgu_id, barangay_id, bank_name, account_number, account_name)
        values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'LBP', '0001-0002', 'Barangay A second') $sql$,
  'a barangay has only one depository account');
insert into accountable_form (lgu_id, barangay_id, form_type, form_name, series, serial_from, serial_to, next_serial)
values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'official_receipt', 'Accountable Form No. 51', 'Booklet 1', 1001, 1050, 1001);
select pg_temp.expect_error(
  $sql$ insert into accountable_form (lgu_id, barangay_id, form_type, form_name, series, serial_from, serial_to, next_serial)
        values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'official_receipt', 'Accountable Form No. 51', 'Booklet 2', 1040, 1090, 1040) $sql$,
  'OR serial ranges cannot overlap');

-- ---------------------------------------------------------------------------
-- As the COA auditor of LGU X: read everything, write nothing
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000003');

select pg_temp.assert((select count(*) from barangay) = 2, 'auditor sees every barangay of the LGU');
select pg_temp.assert((select count(*) from journal_entry) = 4, 'auditor sees all entries');
select pg_temp.assert((select count(*) from audit_log where table_name = 'journal_entry') > 0, 'auditor can read the audit trail');
select pg_temp.expect_error(
  $sql$ insert into supplier (lgu_id, name) values ('10000000-0000-0000-0000-000000000001', 'Nope') $sql$,
  'auditor cannot add master data');
select pg_temp.expect_error(
  $sql$ update journal_entry set description = 'x' where status = 'draft' $sql$ ||
  $sql$; insert into journal_entry (lgu_id, barangay_id, fund_id, book, entry_date, description)
          values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
                  (select id from fund where barangay_id = '20000000-0000-0000-0000-000000000001' and code = 'GF'), 'GJ', '2026-03-01', 'Nope') $sql$,
  'auditor cannot create entries');

-- ---------------------------------------------------------------------------
-- As the Accountant of LGU Y: nothing of LGU X is visible
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000005');

select pg_temp.assert((select count(*) from barangay) = 1, 'another LGU sees only its own barangay');
select pg_temp.assert((select count(*) from journal_entry) = 0, 'another LGU sees none of the entries');
select pg_temp.assert((select count(*) from audit_log where lgu_id = '10000000-0000-0000-0000-000000000001') = 0, 'another LGU sees none of the audit trail');
select pg_temp.assert((select count(*) from general_ledger) = 0, 'another LGU sees an empty ledger');

-- ---------------------------------------------------------------------------
-- Audit trail is complete and append-only
-- ---------------------------------------------------------------------------

reset role;

select pg_temp.assert(
  (select count(*) from audit_log where table_name = 'journal_entry' and action = 'INSERT') = 4
  and (select count(*) from audit_log where table_name = 'journal_line' and action = 'INSERT') = 8
  and (select count(*) from audit_log where table_name = 'period' and action = 'UPDATE') = 1,
  'audit log holds every insert and the period close');
select pg_temp.assert(
  (select changed_by = '00000000-0000-0000-0000-000000000002' from audit_log where table_name = 'period' and action = 'UPDATE'),
  'audit log records who closed the period');
select pg_temp.assert(
  (select barangay_id = '20000000-0000-0000-0000-000000000001' from audit_log where table_name = 'journal_line' limit 1),
  'audit rows for journal lines carry the barangay');
select pg_temp.expect_error($sql$ update audit_log set action = 'UPDATE' where id = (select min(id) from audit_log) $sql$, 'audit log rows cannot be edited');
select pg_temp.expect_error($sql$ delete from audit_log where id = (select min(id) from audit_log) $sql$, 'audit log rows cannot be deleted');

rollback;
