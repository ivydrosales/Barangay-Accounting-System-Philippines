-- Phase 1 rule tests: Disbursement Vouchers, checks, posting, Transmittal Letter.
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
-- Fixtures: Barangay A with a Treasurer, a CCA, a Punong Barangay, an Accountant
-- ---------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'treasurer-a@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'accountant-x@test.local'),
  ('00000000-0000-0000-0000-000000000007', 'cca-a@test.local'),
  ('00000000-0000-0000-0000-000000000008', 'pb-a@test.local');

insert into lgu (id, name, lgu_type, province) values
  ('10000000-0000-0000-0000-000000000001', 'Test City', 'city', 'Test Province');
insert into barangay (id, lgu_id, name) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Barangay A');

insert into user_membership (user_id, lgu_id, barangay_id, role) values
  ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'barangay_treasurer'),
  ('00000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'cca'),
  ('00000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'punong_barangay'),
  ('00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', null, 'lgu_accountant');

insert into official (id, lgu_id, barangay_id, position, full_name, user_id) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Barangay Treasurer', 'Tess Treasurer', '00000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Chairman, Committee on Appropriations', 'Cora Chair', '00000000-0000-0000-0000-000000000007'),
  ('40000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Punong Barangay', 'Pedro Punong', '00000000-0000-0000-0000-000000000008');

insert into bank_account (id, lgu_id, barangay_id, bank_name, branch, account_number, account_name) values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'LBP', 'Main', '0001-0001', 'Barangay A');

insert into accountable_form (id, lgu_id, barangay_id, form_type, form_name, series, serial_from, serial_to, next_serial, issued_to_official_id, received_on) values
  ('60000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'check', 'Check (LBP)', 'Checkbook 1', 100001, 100050, 100001, '40000000-0000-0000-0000-000000000001', '2026-02-20');

insert into supplier (id, lgu_id, name, tin) values
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'ABC Office Supplies', '123-456-789-000');

select set_config('test.gf', (select id::text from fund where barangay_id = '20000000-0000-0000-0000-000000000001' and code = 'GF'), true);

-- ---------------------------------------------------------------------------
-- The Treasurer prepares the voucher
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

do $$
declare
  v_b  uuid := '20000000-0000-0000-0000-000000000001';
  v_gf uuid := current_setting('test.gf')::uuid;
  v_dv disbursement_voucher;
  v_dv2 disbursement_voucher;
begin
  perform pg_temp.expect_error(
    format($q$ insert into disbursement_voucher (lgu_id, barangay_id, fund_id, dv_no, dv_date, payee, particulars, amount)
               values ('10000000-0000-0000-0000-000000000001', %L, %L, 'X', '2026-03-05', 'P', 'p', 1) $q$, v_b, v_gf),
    'DVs cannot be inserted by hand');
  perform pg_temp.expect_error(
    format($q$ select create_dv(%L, %L, '2026-03-05', 'ABC Office Supplies', 'Bond paper', '[]'::jsonb) $q$, v_b, v_gf),
    'a DV needs at least one charge line');
  perform pg_temp.expect_error(
    format($q$ select create_dv(%L, %L, '2026-03-05', 'ABC Office Supplies', 'Bond paper',
                 '[{"kind":"charge","account_code":"4-01-02-010","amount":1000}]'::jsonb) $q$, v_b, v_gf),
    'a DV cannot charge an income account');
  perform pg_temp.expect_error(
    format($q$ select create_dv(%L, %L, '2026-03-05', 'ABC Office Supplies', 'Bond paper',
                 '[{"kind":"charge","account_code":"5-02-03-010","amount":1000},{"kind":"deduction","account_code":"5-02-03-010","amount":50}]'::jsonb) $q$, v_b, v_gf),
    'a deduction must go to a liability account');
  perform pg_temp.expect_error(
    format($q$ select create_dv(%L, %L, '2026-03-05', 'ABC Office Supplies', 'Bond paper',
                 '[{"kind":"charge","account_code":"5-02-03-010","amount":1000},{"kind":"deduction","account_code":"2-02-01-010","amount":1000}]'::jsonb) $q$, v_b, v_gf),
    'deductions cannot swallow the whole claim');

  v_dv := create_dv(v_b, v_gf, '2026-03-05', 'ABC Office Supplies', 'Bond paper and toner for the barangay hall',
                    '[{"kind":"charge","account_code":"5-02-03-010","amount":10000,"particulars":"Office supplies"},
                      {"kind":"deduction","account_code":"2-02-01-010","amount":500,"particulars":"Withholding tax"}]'::jsonb,
                    '123-456-789-000', 'Poblacion', '70000000-0000-0000-0000-000000000001');
  perform pg_temp.assert(v_dv.dv_no = '2026-03-001' and v_dv.status = 'draft' and v_dv.amount = 10000,
    'the first DV is numbered 2026-03-001 for the gross amount 10,000');
  perform pg_temp.assert((select charges = 10000 and deductions = 500 and net_amount = 9500 from dv_totals where dv_id = v_dv.id),
    'Box E totals: charges 10,000, deductions 500, net 9,500');
  perform set_config('test.dv1', v_dv.id::text, true);

  update disbursement_voucher set particulars = 'Bond paper, toner and folders' where id = v_dv.id;
  perform pg_temp.assert((select particulars = 'Bond paper, toner and folders' from disbursement_voucher where id = v_dv.id), 'a draft DV can still be edited');
  perform pg_temp.expect_error(format($q$ update disbursement_voucher set status = 'approved' where id = %L $q$, v_dv.id), 'boxes cannot be signed by editing the row');
  perform pg_temp.expect_error(format($q$ delete from disbursement_voucher where id = %L $q$, v_dv.id), 'a DV is never deleted');
  perform pg_temp.expect_error(format($q$ select certify_dv_box_a(%L) $q$, v_dv.id), 'the Treasurer cannot sign Box A');
  perform pg_temp.expect_error(format($q$ select certify_dv_box_b(%L) $q$, v_dv.id), 'Box B cannot be signed before Box A');
  perform pg_temp.expect_error(format($q$ select issue_check(%L, '60000000-0000-0000-0000-000000000004', '2026-03-06') $q$, v_dv.id), 'no check without Boxes A, B and C');

  -- a second DV that will be cancelled: its number stays in the series
  v_dv2 := create_dv(v_b, v_gf, '2026-03-05', 'Wrong Payee', 'Mistake',
                     '[{"kind":"charge","account_code":"5-02-99-990","amount":100}]'::jsonb);
  perform pg_temp.assert(v_dv2.dv_no = '2026-03-002', 'the second DV is 2026-03-002');
  v_dv2 := cancel_dv(v_dv2.id, 'prepared for the wrong payee');
  perform pg_temp.assert(v_dv2.status = 'cancelled' and v_dv2.dv_no = '2026-03-002', 'a cancelled DV keeps its number');
  perform pg_temp.expect_error(format($q$ update disbursement_voucher set particulars = 'x' where id = %L $q$, v_dv2.id), 'a cancelled DV is frozen');
end $$;

-- ---------------------------------------------------------------------------
-- Box A by the CCA
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000007');

do $$
declare v_dv disbursement_voucher;
begin
  v_dv := certify_dv_box_a(current_setting('test.dv1')::uuid);
  perform pg_temp.assert(v_dv.status = 'certified_a' and v_dv.box_a_by = '00000000-0000-0000-0000-000000000007'
    and v_dv.box_a_official_id = '40000000-0000-0000-0000-000000000003', 'the CCA signs Box A');
  perform pg_temp.expect_error(format($q$ update disbursement_voucher set particulars = 'late edit' where id = %L $q$, v_dv.id), 'after Box A the DV is frozen');
  perform pg_temp.expect_error(format($q$ update dv_line set amount = 1 where dv_id = %L $q$, v_dv.id), 'after Box A the lines are frozen');
  perform pg_temp.expect_error(format($q$ select approve_dv(%L) $q$, v_dv.id), 'Box C cannot be signed before Box B');
  perform pg_temp.expect_error(format($q$ select certify_dv_box_b(%L) $q$, v_dv.id), 'the CCA cannot sign Box B');
end $$;

-- ---------------------------------------------------------------------------
-- Box B by the Treasurer, Box C by the Punong Barangay
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');
select pg_temp.assert((select status = 'certified_b' from certify_dv_box_b(current_setting('test.dv1')::uuid)), 'the Treasurer signs Box B');
select pg_temp.expect_error(format($q$ select approve_dv(%L) $q$, current_setting('test.dv1')), 'the Treasurer cannot sign Box C');

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000008');
select pg_temp.assert(
  (select status = 'approved' and box_c_official_id = '40000000-0000-0000-0000-000000000004' from approve_dv(current_setting('test.dv1')::uuid)),
  'the Punong Barangay approves (Box C)');
select pg_temp.expect_error(format($q$ select issue_check(%L, '60000000-0000-0000-0000-000000000004', '2026-03-06') $q$, current_setting('test.dv1')), 'the Punong Barangay does not draw checks');

-- ---------------------------------------------------------------------------
-- The Treasurer draws the check, the payee receives it
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

do $$
declare
  v_dv  uuid := current_setting('test.dv1')::uuid;
  v_chk bank_check;
  v_row disbursement_voucher;
begin
  perform pg_temp.expect_error(
    format($q$ insert into bank_check (lgu_id, barangay_id, bank_account_id, accountable_form_id, dv_id, check_no, check_date, payee, amount, pbc_no, pbc_date)
               values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000004', %L, 1, '2026-03-06', 'x', 1, 'x', '2026-03-06') $q$, v_dv),
    'checks cannot be inserted by hand');
  v_chk := issue_check(v_dv, '60000000-0000-0000-0000-000000000004', '2026-03-06');
  perform pg_temp.assert(v_chk.check_no = 100001 and v_chk.amount = 9500 and v_chk.pbc_no = '2026-03-001' and v_chk.status = 'issued',
    'check 100001 is drawn for the net 9,500 with PB Certification 2026-03-001');
  perform pg_temp.assert((select next_serial = 100002 from accountable_form where id = '60000000-0000-0000-0000-000000000004'), 'the checkbook moves to the next serial');
  perform pg_temp.assert((select status = 'check_issued' from disbursement_voucher where id = v_dv), 'the DV shows the check issued');
  perform pg_temp.expect_error($q$ update accountable_form set next_serial = 100005 where id = '60000000-0000-0000-0000-000000000004' $q$, 'check serials cannot be skipped');
  perform pg_temp.expect_error($q$ update accountable_form set next_serial = 100001 where id = '60000000-0000-0000-0000-000000000004' $q$, 'check serials cannot be rewound');
  perform pg_temp.expect_error($q$ update accountable_form set serial_to = 100099 where id = '60000000-0000-0000-0000-000000000004' $q$, 'a booklet with issued serials keeps its range');
  insert into accountable_form (lgu_id, barangay_id, form_type, form_name, series, serial_from, serial_to, next_serial)
  values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'check', 'Check (LBP)', 'Checkbook 2', 200001, 200050, 200001);
  update accountable_form set serial_from = 200101, serial_to = 200150, next_serial = 200101 where series = 'Checkbook 2';
  perform pg_temp.assert((select serial_from = 200101 from accountable_form where series = 'Checkbook 2'), 'an unused booklet''s range can be corrected');
  update accountable_form set status = 'returned' where series = 'Checkbook 2';
  perform pg_temp.expect_error($q$ update accountable_form set status = 'on_hand' where series = 'Checkbook 2' $q$, 'a returned booklet stays returned');
  perform pg_temp.expect_error(format($q$ select issue_check(%L, '60000000-0000-0000-0000-000000000004', '2026-03-06') $q$, v_dv), 'one check per DV');
  perform pg_temp.expect_error(format($q$ update bank_check set amount = 1 where id = %L $q$, v_chk.id), 'a check cannot be edited');
  perform pg_temp.expect_error(format($q$ delete from bank_check where id = %L $q$, v_chk.id), 'a check cannot be deleted');
  perform pg_temp.expect_error(format($q$ select cancel_dv(%L, 'late') $q$, v_dv), 'a DV with a check cannot simply be cancelled');

  perform pg_temp.assert(
    (select cib_check = 9500 and cib_balance = -9500 and reference = 'Check No. 100001 / DV 2026-03-001'
     from cashbook('20000000-0000-0000-0000-000000000001', 2026, 3) where seq = 1),
    'the Cashbook shows the check under Cash in Bank - Check Issued');

  perform pg_temp.expect_error(format($q$ select release_check(%L, 'Ana Bautista', '2026-03-01') $q$, v_dv), 'a check cannot be received before its date');
  perform pg_temp.expect_error(format($q$ select post_dv(%L) $q$, v_dv), 'the Treasurer cannot post a DV');
  v_row := release_check(v_dv, 'Ana Bautista', '2026-03-07', 'OR 4455');
  perform pg_temp.assert(v_row.status = 'paid' and v_row.received_by = 'Ana Bautista' and v_row.payee_or_no = 'OR 4455', 'Box D marks the DV paid');
  perform pg_temp.assert((select status = 'released' and released_on = '2026-03-07' from bank_check where id = v_chk.id), 'the check register shows the check released');
end $$;

-- ---------------------------------------------------------------------------
-- The Accountant posts; the Treasurer transmits
-- ---------------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000002');

do $$
declare
  v_dv uuid := current_setting('test.dv1')::uuid;
  v_e  journal_entry;
begin
  v_e := post_dv(v_dv);
  perform pg_temp.assert(v_e.book = 'JCT' and v_e.status = 'posted' and v_e.entry_date = '2026-03-06' and v_e.entry_no = '2026-03-001',
    'the DV posts as JCT 2026-03-001 dated the check date');
  perform pg_temp.assert(
    (select string_agg(account_code || ':' || debit || '/' || credit, ',' order by line_no) from journal_line where entry_id = v_e.id)
    = '5-02-03-010:10000.00/0.00,2-02-01-010:0.00/500.00,1-01-02-010:0.00/9500.00',
    'entry: Dr Office Supplies 10,000 / Cr Due to BIR 500 / Cr Cash in Bank 9,500 (5.3.1 a)');
  perform pg_temp.assert((select subsidiary_type = 'supplier' and subsidiary_id = '70000000-0000-0000-0000-000000000001' from journal_line where entry_id = v_e.id and line_no = 1),
    'the charge carries the supplier as its subsidiary ledger key');
  perform pg_temp.expect_error(format($q$ select post_dv(%L) $q$, v_dv), 'a DV cannot be posted twice');
  perform pg_temp.assert((select sum(balance) = -9500 from trial_balance where account_code = '1-01-02-010'), 'cash in bank is credited 9,500 in the trial balance');
end $$;

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

do $$
declare
  v_b  uuid := '20000000-0000-0000-0000-000000000001';
  v_tl transmittal_letter;
begin
  perform pg_temp.expect_error(format($q$ select prepare_transmittal(%L, 2026, 2) $q$, v_b), 'an empty month has nothing to transmit');
  v_tl := prepare_transmittal(v_b, 2026, 3, '2026-04-08');
  perform pg_temp.assert(v_tl.status = 'draft' and v_tl.treasurer_official_id = '40000000-0000-0000-0000-000000000001' and v_tl.noted_by_official_id = '40000000-0000-0000-0000-000000000004',
    'the draft Transmittal Letter names the Treasurer and the Punong Barangay');
  perform pg_temp.assert((select transmittal_id = v_tl.id from disbursement_voucher where id = current_setting('test.dv1')::uuid), 'the paid DV is listed on it');
  insert into tl_other_report (transmittal_id, report_date, report_type) values (v_tl.id, '2026-03-31', 'Certified copy of the Cashbook');
  perform pg_temp.expect_error(format($q$ update transmittal_letter set status = 'submitted', tl_no = 'X' where id = %L $q$, v_tl.id), 'a TL is submitted only through submit_transmittal()');
  perform pg_temp.expect_error(format($q$ select receive_transmittal(%L, 'Clerk') $q$, v_tl.id), 'the Treasurer cannot acknowledge receipt');

  v_tl := submit_transmittal(v_tl.id);
  perform pg_temp.assert(v_tl.status = 'submitted' and v_tl.tl_no = '2026-04-001', 'the submitted TL is numbered 2026-04-001');
  perform pg_temp.expect_error(format($q$ insert into tl_other_report (transmittal_id, report_date, report_type) values (%L, '2026-03-31', 'late') $q$, v_tl.id), 'a submitted TL list is frozen');
  perform pg_temp.expect_error(format($q$ update disbursement_voucher set transmittal_id = null where id = %L $q$, current_setting('test.dv1')), 'a DV cannot leave a submitted TL');
  perform pg_temp.expect_error(format($q$ delete from transmittal_letter where id = %L $q$, v_tl.id), 'a submitted TL cannot be deleted');
  perform set_config('test.tl1', v_tl.id::text, true);
end $$;

reset role;
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000002');
select pg_temp.assert(
  (select status = 'received' and received_by = 'Rita Receiving' from receive_transmittal(current_setting('test.tl1')::uuid, 'Rita Receiving')),
  'the Accountant''s office acknowledges receipt of the TL');

rollback;
