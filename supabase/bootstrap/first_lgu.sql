-- One-time setup: the first LGU, its barangays and your own administrator login.
--
-- 1. Create your login first: Supabase > Authentication > Users > Add user.
-- 2. Change the five values in the block below.
-- 3. Paste the whole file into Supabase > SQL Editor and run it.
--
-- Running it twice creates a second LGU with the same name, so run it once.

do $$
declare
  -- ------------------------------------------------------------------ edit me
  v_email     text     := 'you@example.com';
  v_lgu_name  text     := 'Pilot City';
  v_lgu_type  lgu_type := 'city';                 -- 'city' or 'municipality'
  v_province  text     := 'Province';
  v_barangays text[]   := array['Barangay One', 'Barangay Two', 'Barangay Three'];
  -- ---------------------------------------------------------------------------
  v_user uuid;
  v_lgu  uuid;
  b      text;
begin
  select id into v_user from auth.users where email = v_email;
  if v_user is null then
    raise exception 'No login with email %. Add it under Authentication > Users first.', v_email;
  end if;

  insert into lgu (name, lgu_type, province)
  values (v_lgu_name, v_lgu_type, v_province)
  returning id into v_lgu;

  foreach b in array v_barangays loop
    insert into barangay (lgu_id, name) values (v_lgu, b);   -- standard funds are created automatically
  end loop;

  insert into user_membership (user_id, lgu_id, role) values
    (v_user, v_lgu, 'lgu_admin'),
    (v_user, v_lgu, 'lgu_accountant');

  raise notice 'Created % with % barangay(s); % is LGU admin and Accountant.', v_lgu_name, array_length(v_barangays, 1), v_email;
end $$;
