-- Phase 1 rule tests: Official Receipts, RCR, RCD, posting and the Cashbook.
-- Run with scripts/db-test.sh. Everything here is rolled back.

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

create function pg_temp.login(p_user uuid) returns void
language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true)
$$;

-- ---------------------------------------------------------------------------
-- Fixtures: LGU X with Barangay A; a treasurer, a collector and an accountant
-- ---------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'treasurer-a@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'accountant-x@test.local'),
  ('00000000-0000-0000-0000-000000000006', 'collector-a@test.local');

insert into lgu (id, name, lgu_type, province) values
  ('10000000-0000-0000-0000-000000000001', 'Test City', 'city', 'Test Province');

insert into barangay (id, lgu_id, name) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Barangay A');

insert into user_membership (user_id, lgu_id, barangay_id, role) values
  ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'barangay_treasurer'),
  ('00000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'deputized_collector'),
  ('00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', null, 'lgu_accountant');

insert into official (id, lgu_id, barangay_id, position, full_name, user_id) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Barangay Treasurer', 'Tess Treasurer', '00000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Deputized Barangay Collector', 'Carlo Collector', '00000000-0000-0000-0000-000000000006');

insert into bank_account (id, lgu_id, barangay_id, bank_name, branch, account_number, account_name) values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'LBP', 'Main', '0001-0001', 'Barangay A');

-- OR booklets: the treasurer's has only five receipts so it runs out in the test
insert into accountable_form (id, lgu_id, barangay_id, form_type, form_name, series, serial_from, serial_to, next_serial, issued_to_official_id, received_on) values
  ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'official_receipt', 'Official Receipt (AF 51)', 'Booklet 1', 1001, 1005, 1001, '40000000-0000-0000-0000-000000000001', '2026-02-20'),
  ('60000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'official_receipt', 'Official Receipt (AF 51)', 'Booklet 2', 5001, 5050, 5001, '40000000-0000-0000-0000-000000000002', '2026-02-20'),
  ('60000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'cash_ticket', 'Cash Tickets', 'Roll 1', 1, 500, 1, '40000000-0000-0000-0000-000000000001', '2026-02-20');

select pg_temp.assert((select count(*) from collection_type where lgu_id = '10000000-0000-0000-0000-000000000001') = 14, 'a new LGU gets the default natures of collection');
select pg_temp.expect_error(
  $sql$ insert into collection_type (lgu_id, name, account_code) values ('10000000-0000-0000-0000-000000000001', 'Wrong', '5-01-01-010') $sql$,
  'a nature of collection cannot credit an expense account');

select set_config('test.gf', (select id::text from fund where barangay_id = '20000000-0000-0000-0000-000000000001' and code = 'GF'), true);
select set_config('test.sk', (select id::text from fund where barangay_id = '20000000-0000-0000-0000-000000000001' and code = 'SK'), true);
select set_config('test.ct_clearance', (select id::text from collection_type where lgu_id = '10000000-0000-0000-0000-000000000001' and name = 'Clearance and Certification Fees'), true);
select set_config('test.ct_business',  (select id::text from collection_type where lgu_id = '10000000-0000-0000-0000-000000000001' and name = 'Business Tax'), true);
select set_config('test.ct_garbage',   (select id::text from collection_type where lgu_id = '10000000-0000-0000-0000-000000000001' and name = 'Garbage Fees'), true);
select set_config('test.ct_other',     (select id::text from collection_type where lgu_id = '10000000-0000-0000-0000-000000000001' and name = 'Other Service Revenue'), true);
select set_config('test.ct_market',    (select id::text from collection_type where lgu_id = '10000000-0000-0000-0000-000000000001' and name = 'Market Fees'), true);

-- ---------------------------------------------------------------------------
-- The treasurer issues Official Receipts
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

do $$
declare
  v_form uuid := '60000000-0000-0000-0000-000000000001';
  v_gf   uuid := current_setting('test.gf')::uuid;
  v_or   official_receipt;
begin
  perform pg_temp.expect_error(
    format($q$ insert into official_receipt (lgu_id, barangay_id, accountable_form_id, serial_no, or_date, payor, collection_type_id, nature, fund_id, amount)
               values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', %L, 1001, '2026-03-02', 'X', %L, 'x', %L, 1) $q$,
           v_form, current_setting('test.ct_clearance'), v_gf),
    'ORs cannot be inserted by hand');

  v_or := issue_official_receipt(v_form, '2026-03-02', 'Juan dela Cruz', current_setting('test.ct_clearance')::uuid, v_gf, 150);
  perform pg_temp.assert(v_or.serial_no = 1001 and v_or.status = 'issued' and v_or.nature = 'Clearance and Certification Fees',
    'first OR takes serial 1001 and the nature of collection from the list');
  perform set_config('test.or1', v_or.id::text, true);

  perform pg_temp.expect_error(
    format($q$ select issue_official_receipt(%L, '2026-03-02', 'Tindahan ni Aling Nena', %L, %L, 500, 'check') $q$, v_form, current_setting('test.ct_business'), v_gf),
    'a check payment needs the bank and check number');
  v_or := issue_official_receipt(v_form, '2026-03-02', 'Tindahan ni Aling Nena', current_setting('test.ct_business')::uuid, v_gf, 500,
                                 'check', 'LBP', '123456', '2026-03-01');
  perform pg_temp.assert(v_or.serial_no = 1002 and v_or.payment_mode = 'check', 'second OR takes serial 1002');

  perform pg_temp.expect_error(
    format($q$ select issue_official_receipt(%L, '2026-03-01', 'Backdated', %L, %L, 10) $q$, v_form, current_setting('test.ct_clearance'), v_gf),
    'an OR cannot be dated before the previous OR of the booklet');
  perform pg_temp.expect_error(
    format($q$ select issue_official_receipt(%L, '2026-03-02', '', %L, %L, 10) $q$, v_form, current_setting('test.ct_clearance'), v_gf),
    'the payor is required');
  perform pg_temp.expect_error(
    format($q$ select issue_official_receipt(%L, '2026-03-02', 'Zero', %L, %L, 0) $q$, v_form, current_setting('test.ct_clearance'), v_gf),
    'the amount must be positive');
  perform pg_temp.expect_error(
    format($q$ select issue_official_receipt('60000000-0000-0000-0000-000000000003', '2026-03-02', 'Ticket', %L, %L, 5) $q$, current_setting('test.ct_market'), v_gf),
    'cash tickets are not issued as Official Receipts');

  v_or := issue_official_receipt(v_form, '2026-03-02', 'Spoiled', current_setting('test.ct_clearance')::uuid, v_gf, 100);
  perform pg_temp.expect_error(format($q$ select cancel_official_receipt(%L, '') $q$, v_or.id), 'cancelling needs a reason');
  v_or := cancel_official_receipt(v_or.id, 'wrong payor written');
  perform pg_temp.assert(v_or.serial_no = 1003 and v_or.status = 'cancelled' and v_or.cancelled_at is not null, 'OR 1003 is cancelled and kept');
  perform pg_temp.expect_error(format($q$ update official_receipt set status = 'issued' where id = %L $q$, v_or.id), 'a cancelled OR stays cancelled');
  perform pg_temp.expect_error(format($q$ delete from official_receipt where id = %L $q$, v_or.id), 'ORs are never deleted');
  perform pg_temp.expect_error(format($q$ update official_receipt set serial_no = 1999 where id = %L $q$, v_or.id), 'serial numbers never change');

  v_or := issue_official_receipt(v_form, '2026-03-02', 'Mang Tomas', current_setting('test.ct_garbage')::uuid, v_gf, 250);
  v_or := issue_official_receipt(v_form, '2026-03-02', 'Aling Rosa', current_setting('test.ct_other')::uuid, v_gf, 75);
  perform pg_temp.assert(v_or.serial_no = 1005, 'serials run 1001 to 1005 without gaps');
  perform pg_temp.assert((select status = 'used_up' and next_serial = 1006 from accountable_form where id = v_form), 'the booklet is marked used up after its last receipt');
  perform pg_temp.expect_error(
    format($q$ select issue_official_receipt(%L, '2026-03-02', 'One too many', %L, %L, 10) $q$, v_form, current_setting('test.ct_clearance'), v_gf),
    'no OR can be issued from a used-up booklet');
end $$;

-- ---------------------------------------------------------------------------
-- The collector issues ORs and reports them on an RCR
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000006');

do $$
declare
  v_form uuid := '60000000-0000-0000-0000-000000000002';
  v_gf   uuid := current_setting('test.gf')::uuid;
  v_or   official_receipt;
  v_rcr  rcr;
begin
  v_or := issue_official_receipt(v_form, '2026-03-02', 'Stall 12', current_setting('test.ct_market')::uuid, v_gf, 30);
  v_or := issue_official_receipt(v_form, '2026-03-02', 'Stall 14', current_setting('test.ct_market')::uuid, v_gf, 20);
  perform pg_temp.assert(v_or.serial_no = 5002 and v_or.collector_official_id = '40000000-0000-0000-0000-000000000002',
    'collector ORs come from the collector''s own booklet and carry the collector');

  perform pg_temp.expect_error(
    $q$ select prepare_rcr('20000000-0000-0000-0000-000000000001', '2026-03-02', '40000000-0000-0000-0000-000000000001') $q$,
    'an RCR with no ORs cannot be prepared');
  v_rcr := prepare_rcr('20000000-0000-0000-0000-000000000001', '2026-03-02', '40000000-0000-0000-0000-000000000002');
  perform pg_temp.assert(v_rcr.status = 'draft' and v_rcr.rcr_no is null
    and (select count(*) from official_receipt where rcr_id = v_rcr.id) = 2
    and (select total = 50 and cash = 50 and checks = 0 from rcr_totals where rcr_id = v_rcr.id),
    'the draft RCR lists the collector''s two ORs, total 50');
  perform pg_temp.expect_error(format($q$ update rcr set status = 'certified', rcr_no = 'X' where id = %L $q$, v_rcr.id), 'an RCR is certified only through certify_rcr()');
  perform pg_temp.expect_error(format($q$ select acknowledge_rcr(%L) $q$, v_rcr.id), 'the treasurer cannot acknowledge an RCR before it is certified');

  v_rcr := certify_rcr(v_rcr.id);
  perform pg_temp.assert(v_rcr.status = 'certified' and v_rcr.rcr_no = '2026-03-001', 'the certified RCR is numbered 2026-03-001');
  perform pg_temp.expect_error(format($q$ update official_receipt set payor = 'Changed' where id = %L $q$, v_or.id), 'ORs on a certified RCR are frozen');
  perform pg_temp.expect_error(format($q$ delete from rcr where id = %L $q$, v_rcr.id), 'a certified RCR cannot be deleted');
  perform set_config('test.rcr1', v_rcr.id::text, true);
end $$;

-- ---------------------------------------------------------------------------
-- The treasurer acknowledges the RCR, records the deposit and prepares the RCD
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

do $$
declare
  v_b   uuid := '20000000-0000-0000-0000-000000000001';
  v_rcr rcr;
  v_rcd rcd;
  v_dep uuid;
begin
  v_rcr := acknowledge_rcr(current_setting('test.rcr1')::uuid);
  perform pg_temp.assert(v_rcr.status = 'acknowledged' and v_rcr.acknowledged_by = '00000000-0000-0000-0000-000000000001', 'the treasurer acknowledges receipt of the collector''s cash');

  insert into deposit (lgu_id, barangay_id, bank_account_id, fund_id, deposit_date, reference, amount)
  values ('10000000-0000-0000-0000-000000000001', v_b, '50000000-0000-0000-0000-000000000001', current_setting('test.gf')::uuid, '2026-03-02', 'DS 778899', 1025)
  returning id into v_dep;

  v_rcd := prepare_rcd(v_b, '2026-03-02');
  perform pg_temp.assert(v_rcd.status = 'draft' and v_rcd.treasurer_official_id = '40000000-0000-0000-0000-000000000001', 'the draft RCD names the Barangay Treasurer');
  perform pg_temp.assert(
    (select count(*) from official_receipt where rcd_id = v_rcd.id) = 5
    and (select count(*) from rcr where rcd_id = v_rcd.id) = 1
    and (select count(*) from deposit where rcd_id = v_rcd.id) = 1,
    'the RCD picks up the 5 treasurer ORs (cancelled one included), the acknowledged RCR and the deposit');
  perform pg_temp.assert((select collections = 1025 and deposits = 1025 from rcd_totals where rcd_id = v_rcd.id),
    'collections total 1025 (975 own + 50 per RCR) and deposits 1025');
  perform pg_temp.assert(
    (select count(*) from rcd_collection_lines(v_rcd.id)) = 6
    and (select amount is null and is_cancelled from rcd_collection_lines(v_rcd.id) where number = '1003')
    and (select number = 'RCR 2026-03-001' and amount = 50 from rcd_collection_lines(v_rcd.id) where kind = 'RCR'),
    'section A lists six lines in order, the cancelled OR without an amount');
  perform pg_temp.assert(
    (select iss_qty = 5 and iss_from = 1001 and iss_to = 1005 and end_qty = 0 and beg_qty = 5 and beg_from = 1001
     from report_accountable_forms(v_b, '2026-03-02') where series = 'Booklet 1'),
    'section C shows Booklet 1 fully issued today: 5 on hand, 5 issued, 0 left');
  perform pg_temp.assert(
    (select iss_qty = 2 and end_qty = 48 and end_from = 5003 and end_to = 5050
     from report_accountable_forms(v_b, '2026-03-02') where series = 'Booklet 2'),
    'section C shows Booklet 2 with 48 receipts left from 5003');
  perform pg_temp.expect_error($q$ select prepare_rcd('20000000-0000-0000-0000-000000000001', '2026-03-03') $q$, 'only one draft RCD at a time');
  perform pg_temp.expect_error(format($q$ update rcd set status = 'certified', rcd_no = 'X' where id = %L $q$, v_rcd.id), 'an RCD is certified only through certify_rcd()');
  perform pg_temp.expect_error(format($q$ select post_rcd(%L) $q$, v_rcd.id), 'the treasurer cannot post an RCD');

  v_rcd := certify_rcd(v_rcd.id);
  perform pg_temp.assert(v_rcd.status = 'certified' and v_rcd.rcd_no = '2026-03-001' and v_rcd.certified_by = '00000000-0000-0000-0000-000000000001',
    'the certified RCD is numbered 2026-03-001');
  perform pg_temp.expect_error(format($q$ update official_receipt set payor = 'Changed' where id = %L $q$, current_setting('test.or1')), 'ORs on a certified RCD are frozen');
  perform pg_temp.expect_error(format($q$ update deposit set amount = 1 where id = %L $q$, v_dep), 'deposits on a certified RCD are frozen');
  perform pg_temp.expect_error(format($q$ delete from deposit where id = %L $q$, v_dep), 'deposits on a certified RCD cannot be deleted');
  perform pg_temp.expect_error(format($q$ update rcd set remarks = 'x' where id = %L $q$, v_rcd.id), 'a certified RCD is frozen');
  perform pg_temp.expect_error(format($q$ select cancel_official_receipt(%L, 'late') $q$, current_setting('test.or1')), 'a reported OR cannot be cancelled any more');
  perform set_config('test.rcd1', v_rcd.id::text, true);

  perform pg_temp.assert(
    (select count(*) from cashbook(v_b, 2026, 3)) = 2
    and (select clt_balance = 0 and cib_balance = 0 from cashbook(v_b, 2026, 3) where seq = 0)
    and (select clt_collection = 1025 and clt_deposit = 1025 and clt_balance = 0 and cib_deposit = 1025 and cib_balance = 1025
         and reference = 'RCD No. 2026-03-001' from cashbook(v_b, 2026, 3) where seq = 1),
    'the March Cashbook shows the RCD: 1025 collected, 1025 deposited, bank balance 1025');
  perform pg_temp.assert((select cib_balance = 1025 and clt_balance = 0 from cashbook(v_b, 2026, 4) where seq = 0),
    'April opens with the balances carried forward');
end $$;

-- ---------------------------------------------------------------------------
-- The accountant posts the RCD to the JCT
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000002');

do $$
declare
  v_rcd uuid := current_setting('test.rcd1')::uuid;
  v_n   int;
begin
  select count(*) into v_n from post_rcd(v_rcd);
  perform pg_temp.assert(v_n = 2, 'posting creates two JCT entries: collections and deposit');
  perform pg_temp.assert((select status = 'posted' from rcd where id = v_rcd), 'the RCD is marked posted');
  perform pg_temp.expect_error(format($q$ select post_rcd(%L) $q$, v_rcd), 'an RCD cannot be posted twice');

  perform pg_temp.assert(
    (select e.book = 'JCT' and e.entry_no = '2026-03-001' and e.status = 'posted'
     from journal_entry e where e.source_id = v_rcd and e.description like 'To record collections%'),
    'the collections entry is JCT 2026-03-001');
  perform pg_temp.assert(
    (select l.debit = 1025 from journal_line l join journal_entry e on e.id = l.entry_id
     where e.source_id = v_rcd and e.description like 'To record collections%' and l.account_code = '1-01-01-010'),
    'collections debit Cash - In Local Treasury 1025');
  perform pg_temp.assert(
    (select string_agg(l.account_code || '=' || l.credit, ',' order by l.account_code)
     from journal_line l join journal_entry e on e.id = l.entry_id
     where e.source_id = v_rcd and e.description like 'To record collections%' and l.credit > 0)
    = '4-01-02-010=500.00,4-04-01-010=150.00,4-04-01-990=75.00,4-04-02-010=250.00,4-04-02-020=50.00',
    'collections credit each income account per the nature of collection (cancelled OR excluded)');
  perform pg_temp.assert(
    (select l1.debit = 1025 and l1.account_code = '1-01-02-010' and l1.subsidiary_type = 'bank_account' and l2.credit = 1025 and l2.account_code = '1-01-01-010'
     from journal_entry e
     join journal_line l1 on l1.entry_id = e.id and l1.line_no = 1
     join journal_line l2 on l2.entry_id = e.id and l2.line_no = 2
     where e.source_id = v_rcd and e.description like 'To record deposit%'),
    'the deposit entry is Dr Cash in Bank / Cr Cash - In Local Treasury 1025');
  perform pg_temp.assert(
    (select sum(balance) = 0 from trial_balance where account_code = '1-01-01-010')
    and (select sum(balance) = 1025 from trial_balance where account_code = '1-01-02-010')
    and (select sum(balance) = 1025 from trial_balance where class = 'Revenue'),
    'trial balance: cash on hand 0, cash in bank 1025, income 1025');
end $$;

rollback;
