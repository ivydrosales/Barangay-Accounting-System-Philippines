-- Pilot readiness, migration 9: the LGU administrator gives people access
-- from the app, by email, instead of writing SQL.
--
--   Logins are still created in Supabase (Authentication > Users); this
--   links an existing login to a role in the LGU or in one of its barangays.
--   lgu_members() lists who has access, with their emails, for LGU staff.
--   The last active LGU administrator cannot be removed.

create or replace function grant_access(p_lgu uuid, p_email text, p_role app_role, p_barangay uuid default null)
returns user_membership
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_row  user_membership;
begin
  if not is_lgu_admin(p_lgu) then
    raise exception 'only the LGU administrator gives access' using errcode = '42501';
  end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then
    raise exception 'there is no login with the email %; create it first in Supabase under Authentication > Users', trim(p_email);
  end if;
  if p_role in ('lgu_accountant', 'lgu_bookkeeper', 'lgu_admin', 'coa_auditor') then
    if p_barangay is not null then
      raise exception 'this role covers the whole city or municipality; leave the barangay empty';
    end if;
  else
    if p_barangay is null then
      raise exception 'choose the barangay for this role';
    end if;
    if not exists (select 1 from barangay where id = p_barangay and lgu_id = p_lgu) then
      raise exception 'that barangay is not part of this city or municipality';
    end if;
  end if;

  insert into user_membership (user_id, lgu_id, barangay_id, role)
  values (v_user, p_lgu, p_barangay, p_role)
  on conflict (user_id, lgu_id, barangay_id, role) do update set is_active = true
  returning * into v_row;
  return v_row;
end $$;

create or replace function revoke_access(p_membership uuid) returns user_membership
language plpgsql security definer set search_path = public as $$
declare v_row user_membership;
begin
  select * into v_row from user_membership where id = p_membership for update;
  if v_row.id is null or not is_lgu_admin(v_row.lgu_id) then
    raise exception 'only the LGU administrator removes access' using errcode = '42501';
  end if;
  if v_row.role = 'lgu_admin' and v_row.is_active and not exists (
       select 1 from user_membership m
       where m.lgu_id = v_row.lgu_id and m.role = 'lgu_admin' and m.is_active and m.id <> v_row.id) then
    raise exception 'this is the last LGU administrator; give the role to someone else first';
  end if;
  update user_membership set is_active = false where id = p_membership
  returning * into v_row;
  return v_row;
end $$;

create or replace function lgu_members(p_lgu uuid)
returns table (membership_id uuid, email text, role app_role, barangay_id uuid, barangay_name text, is_active boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, u.email::text, m.role, m.barangay_id, b.name, m.is_active, m.created_at
  from user_membership m
  join auth.users u on u.id = m.user_id
  left join barangay b on b.id = m.barangay_id
  where m.lgu_id = p_lgu and is_lgu_staff(p_lgu)
  order by m.is_active desc, b.name nulls first, m.role, u.email
$$;

grant execute on function grant_access(uuid, text, app_role, uuid), revoke_access(uuid), lgu_members(uuid) to authenticated, service_role;
revoke all on function grant_access(uuid, text, app_role, uuid), revoke_access(uuid), lgu_members(uuid) from anon, public;
