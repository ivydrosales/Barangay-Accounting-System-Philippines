-- Pilot readiness rule tests: the LGU administrator gives and removes access.
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

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'admin@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'Treasurer.A@Test.local'),
  ('00000000-0000-0000-0000-000000000003', 'admin-y@test.local');

insert into lgu (id, name, lgu_type, province) values
  ('10000000-0000-0000-0000-000000000001', 'Test City', 'city', 'Test Province'),
  ('10000000-0000-0000-0000-000000000002', 'Other Town', 'municipality', 'Test Province');
insert into barangay (id, lgu_id, name) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Barangay A'),
  ('20000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000002', 'Barangay Z');
insert into user_membership (user_id, lgu_id, barangay_id, role) values
  ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', null, 'lgu_admin'),
  ('00000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', null, 'lgu_admin');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000000001');

do $$
declare
  v_lgu uuid := '10000000-0000-0000-0000-000000000001';
  v_b   uuid := '20000000-0000-0000-0000-000000000001';
  v_m   user_membership;
  v_m2  user_membership;
  v_own uuid;
begin
  v_m := grant_access(v_lgu, '  treasurer.a@test.local ', 'barangay_treasurer', v_b);
  perform pg_temp.assert(v_m.user_id = '00000000-0000-0000-0000-000000000002' and v_m.barangay_id = v_b and v_m.is_active,
    'the administrator gives the Treasurer access by email, whatever the capitals and spaces');
  perform pg_temp.expect_error(format($q$ select grant_access(%L, 'nobody@test.local', 'cca', %L) $q$, v_lgu, v_b), 'an email with no login is refused');
  perform pg_temp.expect_error(format($q$ select grant_access(%L, 'treasurer.a@test.local', 'cca', null) $q$, v_lgu), 'a barangay role needs its barangay');
  perform pg_temp.expect_error(format($q$ select grant_access(%L, 'treasurer.a@test.local', 'lgu_accountant', %L) $q$, v_lgu, v_b), 'an LGU role takes no barangay');
  perform pg_temp.expect_error(format($q$ select grant_access(%L, 'treasurer.a@test.local', 'cca', '20000000-0000-0000-0000-000000000009') $q$, v_lgu),
    'a barangay of another LGU is refused');
  perform pg_temp.expect_error($q$ select grant_access('10000000-0000-0000-0000-000000000002', 'treasurer.a@test.local', 'lgu_accountant', null) $q$,
    'an administrator cannot give access in another LGU');

  perform pg_temp.assert((select count(*) = 2 from lgu_members(v_lgu)), 'the administrator sees both people with access');
  perform pg_temp.assert((select email = 'Treasurer.A@Test.local' and barangay_name = 'Barangay A' from lgu_members(v_lgu) where role = 'barangay_treasurer'),
    'with their emails and barangays');
  perform pg_temp.assert((select count(*) = 0 from lgu_members('10000000-0000-0000-0000-000000000002')), 'but nobody of another LGU');

  v_m := revoke_access(v_m.id);
  perform pg_temp.assert(not v_m.is_active, 'access can be removed');
  v_m2 := grant_access(v_lgu, 'treasurer.a@test.local', 'barangay_treasurer', v_b);
  perform pg_temp.assert(v_m2.id = v_m.id and v_m2.is_active, 'and given back without a duplicate');

  select id into v_own from user_membership where user_id = '00000000-0000-0000-0000-000000000001' and role = 'lgu_admin';
  perform pg_temp.expect_error(format('select revoke_access(%L)', v_own), 'the last LGU administrator cannot be removed');
end $$;

select pg_temp.login('00000000-0000-0000-0000-000000000002');
select pg_temp.expect_error($q$ select grant_access('10000000-0000-0000-0000-000000000001', 'admin-y@test.local', 'cca', '20000000-0000-0000-0000-000000000001') $q$,
  'a Treasurer cannot give access');
select pg_temp.assert((select count(*) = 0 from lgu_members('10000000-0000-0000-0000-000000000001')), 'a Treasurer does not see the list of people');

rollback;
