-- Phase 0, migration 2: tenants, memberships, access helpers and master data.
--
-- A tenant is a city or municipality (lgu). Barangays belong to it. The
-- C/M Accountant's office sees every barangay of its LGU; barangay officers
-- see only theirs; COA auditors read everything and write nothing.
-- Row-level security is applied in migration 4, after every table exists.

-- ---------------------------------------------------------------------------
-- Tenants
-- ---------------------------------------------------------------------------

create table lgu (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  lgu_type    lgu_type not null,
  province    text,
  region      text,
  psgc_code   text,                       -- Philippine Standard Geographic Code
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (name, province)
);

create table barangay (
  id          uuid primary key default gen_random_uuid(),
  lgu_id      uuid not null references lgu(id),
  name        text not null,
  psgc_code   text,
  address     text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (lgu_id, name),
  unique (id, lgu_id)                     -- lets child tables pin lgu_id to the barangay
);

-- ---------------------------------------------------------------------------
-- Who may see what
-- ---------------------------------------------------------------------------

create table user_membership (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  lgu_id      uuid not null references lgu(id),
  barangay_id uuid references barangay(id),
  role        app_role not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- LGU-level roles have no barangay; barangay roles must name one.
  constraint membership_scope check (
    (role in ('lgu_accountant', 'lgu_bookkeeper', 'lgu_admin', 'coa_auditor')) = (barangay_id is null)
  ),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique nulls not distinct (user_id, lgu_id, barangay_id, role)
);

create index on user_membership (user_id) where is_active;

-- The helpers below are SECURITY DEFINER so policies can consult
-- user_membership without recursing into its own policy.

create or replace function has_lgu_access(p_lgu uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_membership m
    where m.user_id = auth.uid() and m.is_active and m.lgu_id = p_lgu
  )
$$;

create or replace function has_barangay_access(p_barangay uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from user_membership m
    join barangay b on b.lgu_id = m.lgu_id
    where m.user_id = auth.uid() and m.is_active and b.id = p_barangay
      and (m.barangay_id is null or m.barangay_id = p_barangay)
  )
$$;

-- Read access to a row: LGU-wide rows need LGU access, barangay rows need
-- access to that barangay.
create or replace function can_read(p_lgu uuid, p_barangay uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_barangay is null then has_lgu_access(p_lgu)
    else has_barangay_access(p_barangay)
  end
$$;

-- Write access: any non-auditor membership that covers the row.
create or replace function can_write(p_lgu uuid, p_barangay uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_membership m
    where m.user_id = auth.uid() and m.is_active
      and m.lgu_id = p_lgu
      and m.role <> 'coa_auditor'
      and (
        -- LGU-wide rows: only LGU-level staff
        (p_barangay is null and m.barangay_id is null)
        -- barangay rows: LGU-level staff or that barangay's own officers
        or (p_barangay is not null and (m.barangay_id is null or m.barangay_id = p_barangay))
      )
  )
$$;

-- Only the Accountant's office and LGU admins (closing periods, master data).
create or replace function is_lgu_staff(p_lgu uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_membership m
    where m.user_id = auth.uid() and m.is_active and m.lgu_id = p_lgu
      and m.role in ('lgu_accountant', 'lgu_bookkeeper', 'lgu_admin')
  )
$$;

-- LGU admins grant and revoke access.
create or replace function is_lgu_admin(p_lgu uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_membership m
    where m.user_id = auth.uid() and m.is_active and m.lgu_id = p_lgu and m.role = 'lgu_admin'
  )
$$;

-- ---------------------------------------------------------------------------
-- Chart of Accounts (manual Chapter XIII). COA-prescribed, shared by all LGUs.
-- Seeded from data/chart_of_accounts.csv; never invent accounts.
-- ---------------------------------------------------------------------------

create table account (
  code              text primary key check (code ~ '^[1-5]-\d{2}-\d{2}-\d{3}$'),
  title             text not null,
  class             account_class not null,
  account_group     text not null,
  sub_group         text,
  normal_balance    normal_balance not null,
  contra_of         text references account(code),
  statement_line    text,
  subsidiary_ledger text,                 -- how the SL is kept, e.g. 'per creditor'
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Officials and signatories
-- ---------------------------------------------------------------------------

create table official (
  id              uuid primary key default gen_random_uuid(),
  lgu_id          uuid not null references lgu(id),
  barangay_id     uuid references barangay(id),     -- null = LGU-level (Accountant, Bookkeeper)
  position        text not null,                     -- as the manual names it: Punong Barangay, Barangay Treasurer, CCA ...
  full_name       text not null,
  term_start      date,
  term_end        date,
  bond_amount     numeric(14,2) check (bond_amount is null or bond_amount >= 0),
  bond_expires_on date,
  user_id         uuid references auth.users(id),    -- their login, when they have one
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id)
);

-- ---------------------------------------------------------------------------
-- Funds: one row per barangay per fund. Standard funds are created with the
-- barangay; STFs are added one per purpose.
-- ---------------------------------------------------------------------------

create table fund (
  id            uuid primary key default gen_random_uuid(),
  lgu_id        uuid not null references lgu(id),
  barangay_id   uuid not null references barangay(id),
  fund_type     fund_type not null,
  code          text not null,                       -- GF, SK, LDRRMF, DF, CA, STF-...
  name          text not null,
  purpose       text,                                -- required for STFs
  source_doc    text,                                -- ordinance, MOA, grant letter
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, code),
  unique (id, barangay_id),                          -- lets postings pin fund to barangay
  constraint stf_needs_purpose check (fund_type <> 'stf' or purpose is not null)
);

-- Every barangay gets the five standard funds the moment it is created.
create or replace function seed_standard_funds() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into fund (lgu_id, barangay_id, fund_type, code, name) values
    (new.lgu_id, new.id, 'general',     'GF',     'General Fund'),
    (new.lgu_id, new.id, 'sk',          'SK',     '10% Sangguniang Kabataan Fund'),
    (new.lgu_id, new.id, 'ldrrmf',      'LDRRMF', '5% Local Disaster Risk Reduction and Management Fund'),
    (new.lgu_id, new.id, 'development', 'DF',     '20% Development Fund'),
    (new.lgu_id, new.id, 'continuing',  'CA',     'Continuing Appropriations');
  return new;
end $$;

create trigger barangay_seed_funds
  after insert on barangay
  for each row execute function seed_standard_funds();

-- ---------------------------------------------------------------------------
-- Bank accounts. Manual 4.1.15: one depository account per barangay.
-- ---------------------------------------------------------------------------

create table bank_account (
  id              uuid primary key default gen_random_uuid(),
  lgu_id          uuid not null references lgu(id),
  barangay_id     uuid not null references barangay(id),
  bank_name       text not null,
  branch          text,
  account_number  text not null,
  account_name    text not null,
  account_type    text not null default 'current' check (account_type in ('current', 'savings', 'time_deposit')),
  gl_account_code text not null default '1-01-02-010' references account(code),
  is_depository   boolean not null default true,
  opened_on       date,
  closed_on       date,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, account_number)
);

create unique index one_depository_per_barangay
  on bank_account (barangay_id)
  where is_depository and closed_on is null;

-- ---------------------------------------------------------------------------
-- Suppliers (LGU-wide), employees (per barangay)
-- ---------------------------------------------------------------------------

create table supplier (
  id          uuid primary key default gen_random_uuid(),
  lgu_id      uuid not null references lgu(id),
  name        text not null,
  tin         text,
  address     text,
  contact     text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (lgu_id, name)
);

create table employee (
  id                uuid primary key default gen_random_uuid(),
  lgu_id            uuid not null references lgu(id),
  barangay_id       uuid not null references barangay(id),
  employee_no       text,
  full_name         text not null,
  position          text,
  employment_status text,                             -- elective, appointive, job order ...
  tin               text,
  gsis_no           text,
  pagibig_no        text,
  philhealth_no     text,
  monthly_rate      numeric(14,2) check (monthly_rate is null or monthly_rate >= 0),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  unique (barangay_id, employee_no)
);

-- ---------------------------------------------------------------------------
-- Accountable forms: OR booklets, cash tickets, check booklets, each a serial
-- range. Ranges of the same form type never overlap within a barangay.
-- ---------------------------------------------------------------------------

create table accountable_form (
  id                    uuid primary key default gen_random_uuid(),
  lgu_id                uuid not null references lgu(id),
  barangay_id           uuid not null references barangay(id),
  form_type             accountable_form_type not null,
  form_name             text not null,                -- e.g. 'Accountable Form No. 51'
  series                text,                         -- booklet / stub number
  serial_from           bigint not null,
  serial_to             bigint not null,
  next_serial           bigint not null,
  issued_to_official_id uuid references official(id),
  received_on           date,
  status                accountable_form_status not null default 'on_hand',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  foreign key (barangay_id, lgu_id) references barangay(id, lgu_id),
  constraint serial_range check (serial_from <= serial_to),
  constraint next_serial_in_range check (next_serial between serial_from and serial_to + 1),
  constraint no_overlapping_serials exclude using gist (
    barangay_id with =,
    form_type with =,
    int8range(serial_from, serial_to, '[]') with &&
  )
);

-- updated_at on everything
do $$
declare t text;
begin
  foreach t in array array['lgu', 'barangay', 'user_membership', 'account', 'official', 'fund',
                           'bank_account', 'supplier', 'employee', 'accountable_form']
  loop
    execute format('create trigger %I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;
