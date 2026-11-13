-- NEXORA wallet and owner security migration
-- Run this entire script once in Supabase SQL Editor.
-- The owner is determined from the authenticated Supabase JWT email, not a client-side role field.

create extension if not exists pgcrypto;

create or replace function public.is_nexora_owner()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, auth
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'hoba20@nexora.com';
$$;

-- Customer profile metadata. Keep the table compatible with an existing profiles table.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  full_name text not null default '',
  role text not null default 'customer',
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists email text not null default '';
alter table public.profiles add column if not exists full_name text not null default '';
alter table public.profiles add column if not exists role text not null default 'customer';
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('customer','owner'));

create table if not exists public.wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(14,2) not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists public.wallet_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  amount numeric(14,2) not null check (amount <> 0),
  balance_after numeric(14,2) not null check (balance_after >= 0),
  reason text not null,
  entry_type text not null,
  operator_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.wallet_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  request_type text not null check (request_type in ('deposit','withdrawal')),
  amount numeric(14,2) not null check (amount > 0),
  sender_phone text,
  payout_phone text,
  transfer_reference text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.store_settings (
  setting_key text primary key,
  setting_value text not null default '',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

-- Ensure columns exist when the tables were created by an earlier draft.
alter table public.wallets add column if not exists balance numeric(14,2) not null default 0;
alter table public.wallets add column if not exists updated_at timestamptz not null default now();
alter table public.wallet_ledger add column if not exists amount numeric(14,2);
alter table public.wallet_ledger add column if not exists balance_after numeric(14,2);
alter table public.wallet_ledger add column if not exists reason text;
alter table public.wallet_ledger add column if not exists entry_type text;
alter table public.wallet_ledger add column if not exists operator_id uuid references auth.users(id);
alter table public.wallet_ledger add column if not exists created_at timestamptz not null default now();
alter table public.wallet_requests add column if not exists request_type text;
alter table public.wallet_requests add column if not exists amount numeric(14,2);
alter table public.wallet_requests add column if not exists sender_phone text;
alter table public.wallet_requests add column if not exists payout_phone text;
alter table public.wallet_requests add column if not exists transfer_reference text;
alter table public.wallet_requests add column if not exists status text not null default 'pending';
alter table public.wallet_requests add column if not exists review_note text;
alter table public.wallet_requests add column if not exists reviewed_by uuid references auth.users(id);
alter table public.wallet_requests add column if not exists reviewed_at timestamptz;
alter table public.wallet_requests add column if not exists created_at timestamptz not null default now();
alter table public.store_settings add column if not exists setting_value text not null default '';
alter table public.store_settings add column if not exists updated_by uuid references auth.users(id);
alter table public.store_settings add column if not exists updated_at timestamptz not null default now();

-- Create a zero-balance wallet for every new account and backfill existing accounts.
create or replace function public.handle_new_nexora_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  insert into public.profiles(id, email, full_name, role)
  values (
    new.id,
    lower(coalesce(new.email, '')),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case when lower(coalesce(new.email, '')) = 'hoba20@nexora.com' then 'owner' else 'customer' end
  )
  on conflict (id) do update
    set email = excluded.email,
        full_name = excluded.full_name,
        role = excluded.role;

  insert into public.wallets(user_id, balance)
  values (new.id, 0)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_nexora on auth.users;
create trigger on_auth_user_created_nexora
after insert or update of email on auth.users
for each row execute function public.handle_new_nexora_user();

insert into public.profiles(id, email, full_name, role)
select u.id, lower(coalesce(u.email, '')),
       coalesce(u.raw_user_meta_data ->> 'full_name', ''),
       case when lower(coalesce(u.email, '')) = 'hoba20@nexora.com' then 'owner' else 'customer' end
from auth.users u
on conflict (id) do update
set email = excluded.email, full_name = excluded.full_name, role = excluded.role;

insert into public.wallets(user_id, balance)
select u.id, 0 from auth.users u
on conflict (user_id) do nothing;

-- RLS: customers can only see their own records; the owner can see all records.
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.wallet_requests enable row level security;
alter table public.store_settings enable row level security;

drop policy if exists "nexora_profiles_read" on public.profiles;
create policy "nexora_profiles_read" on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_nexora_owner());

drop policy if exists "nexora_wallets_read" on public.wallets;
create policy "nexora_wallets_read" on public.wallets
for select to authenticated
using (user_id = auth.uid() or public.is_nexora_owner());

drop policy if exists "nexora_ledger_read" on public.wallet_ledger;
create policy "nexora_ledger_read" on public.wallet_ledger
for select to authenticated
using (user_id = auth.uid() or public.is_nexora_owner());

drop policy if exists "nexora_requests_read" on public.wallet_requests;
create policy "nexora_requests_read" on public.wallet_requests
for select to authenticated
using (user_id = auth.uid() or public.is_nexora_owner());

drop policy if exists "nexora_requests_insert" on public.wallet_requests;
create policy "nexora_requests_insert" on public.wallet_requests
for insert to authenticated
with check (
  user_id = auth.uid()
  and status = 'pending'
  and reviewed_by is null
  and reviewed_at is null
);

drop policy if exists "nexora_settings_read" on public.store_settings;
create policy "nexora_settings_read" on public.store_settings
for select to anon, authenticated
using (true);

-- Only these SECURITY DEFINER RPCs may alter balances, and each checks the owner JWT.
create or replace function public.owner_adjust_wallet(
  p_user_id uuid,
  p_amount numeric,
  p_reason text
)
returns numeric
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_balance numeric(14,2);
begin
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  if p_amount is null or p_amount = 0 or length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'invalid_adjustment';
  end if;

  select balance into v_balance
  from public.wallets
  where user_id = p_user_id
  for update;
  if not found then raise exception 'wallet_not_found'; end if;
  if v_balance + p_amount < 0 then raise exception 'insufficient_balance'; end if;

  update public.wallets
  set balance = balance + p_amount, updated_at = now()
  where user_id = p_user_id
  returning balance into v_balance;

  insert into public.wallet_ledger(user_id, amount, balance_after, reason, entry_type, operator_id)
  values (p_user_id, p_amount, v_balance, trim(p_reason), 'owner_adjustment', auth.uid());
  return v_balance;
end;
$$;

create or replace function public.owner_review_wallet_request(
  p_request_id bigint,
  p_status text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  r public.wallet_requests%rowtype;
  v_balance numeric(14,2);
  v_delta numeric(14,2);
begin
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  if p_status not in ('approved', 'rejected') then raise exception 'invalid_status'; end if;

  select * into r from public.wallet_requests where id = p_request_id for update;
  if not found or r.status <> 'pending' then raise exception 'request_not_pending'; end if;

  if p_status = 'approved' then
    v_delta := case when r.request_type = 'deposit' then r.amount else -r.amount end;
    select balance into v_balance from public.wallets where user_id = r.user_id for update;
    if not found then raise exception 'wallet_not_found'; end if;
    if v_balance + v_delta < 0 then raise exception 'insufficient_balance'; end if;

    update public.wallets
    set balance = balance + v_delta, updated_at = now()
    where user_id = r.user_id
    returning balance into v_balance;

    insert into public.wallet_ledger(user_id, amount, balance_after, reason, entry_type, operator_id)
    values (
      r.user_id, v_delta, v_balance,
      coalesce(nullif(trim(p_note), ''), 'اعتماد طلب ' || r.request_type),
      'wallet_request_' || r.request_type, auth.uid()
    );
  end if;

  update public.wallet_requests
  set status = p_status, review_note = coalesce(p_note, ''),
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_request_id;
end;
$$;

create or replace function public.owner_set_store_settings(
  p_transfer_number text,
  p_telegram_username text
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_telegram text := regexp_replace(coalesce(p_telegram_username, ''), '^@', '');
begin
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  if length(v_telegram) not between 5 and 32 or v_telegram !~ '^[A-Za-z0-9_]+$' then
    raise exception 'invalid_telegram';
  end if;

  insert into public.store_settings(setting_key, setting_value, updated_by)
  values
    ('transfer_number', coalesce(trim(p_transfer_number), ''), auth.uid()),
    ('telegram_username', v_telegram, auth.uid())
  on conflict (setting_key) do update
  set setting_value = excluded.setting_value,
      updated_by = auth.uid(),
      updated_at = now();
end;
$$;

-- Lock down direct writes. Customers submit requests; all balance changes go through owner RPCs.
revoke all on function public.is_nexora_owner() from public;
revoke all on function public.owner_adjust_wallet(uuid, numeric, text) from public;
revoke all on function public.owner_review_wallet_request(bigint, text, text) from public;
revoke all on function public.owner_set_store_settings(text, text) from public;
grant execute on function public.is_nexora_owner() to authenticated;
grant execute on function public.owner_adjust_wallet(uuid, numeric, text) to authenticated;
grant execute on function public.owner_review_wallet_request(bigint, text, text) to authenticated;
grant execute on function public.owner_set_store_settings(text, text) to authenticated;

revoke insert, update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.wallets from anon, authenticated;
revoke insert, update, delete on public.wallet_ledger from anon, authenticated;
revoke update, delete on public.wallet_requests from anon, authenticated;
revoke insert, update, delete on public.store_settings from anon, authenticated;

grant select on public.profiles, public.wallets, public.wallet_ledger, public.wallet_requests to authenticated;
grant select on public.store_settings to anon, authenticated;
grant insert on public.wallet_requests to authenticated;
grant usage, select on all sequences in schema public to authenticated;
