-- NEXORA consolidated setup for the existing project.
-- Safe rerun: preserves existing products, orders, wallets, balances and owner settings.
-- Does not seed demo products. Run once in the linked Supabase SQL Editor.

-- =====================================================================
-- Included migration: supabase/schema.sql
-- =====================================================================

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
  select exists (
    select 1
    from auth.users u
    where u.id = auth.uid()
      and lower(coalesce(u.email, '')) = 'jo306843@gmail.com'
  );
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
    case when lower(coalesce(new.email, '')) = 'jo306843@gmail.com' then 'owner' else 'customer' end
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
       case when lower(coalesce(u.email, '')) = 'jo306843@gmail.com' then 'owner' else 'customer' end
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


-- =====================================================================
-- Included migration: supabase/commerce_rewards.sql
-- =====================================================================

-- NEXORA catalog and daily rewards
create extension if not exists pgcrypto;
create or replace function public.is_nexora_owner()
returns boolean language sql stable security definer set search_path=pg_catalog,auth
as $$
select exists(select 1 from auth.users u where u.id=auth.uid() and lower(coalesce(u.email,''))='jo306843@gmail.com');
$$;
create table if not exists public.products(id uuid primary key default gen_random_uuid(),name text not null,category text not null default 'عام',price numeric(14,2) not null check(price>0),old_price numeric(14,2) not null default 0,image_url text not null default '',active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.products enable row level security;
drop policy if exists nx_products_read on public.products;
create policy nx_products_read on public.products for select to anon,authenticated using(active or public.is_nexora_owner());
drop policy if exists nx_products_insert on public.products;
create policy nx_products_insert on public.products for insert to authenticated with check(public.is_nexora_owner());
drop policy if exists nx_products_update on public.products;
create policy nx_products_update on public.products for update to authenticated using(public.is_nexora_owner()) with check(public.is_nexora_owner());
drop policy if exists nx_products_delete on public.products;
create policy nx_products_delete on public.products for delete to authenticated using(public.is_nexora_owner());
grant select on public.products to anon,authenticated;
grant insert,update,delete on public.products to authenticated;

create table if not exists public.daily_reward_claims(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,claim_date date not null,amount numeric(14,2) not null check(amount>0),created_at timestamptz not null default now(),unique(user_id,claim_date));
alter table public.daily_reward_claims enable row level security;
drop policy if exists nx_daily_claims_read on public.daily_reward_claims;
create policy nx_daily_claims_read on public.daily_reward_claims for select to authenticated using(user_id=auth.uid() or public.is_nexora_owner());
grant select on public.daily_reward_claims to authenticated;
insert into public.store_settings(setting_key,setting_value) values('daily_reward_amount','20') on conflict(setting_key) do nothing;

create or replace function public.owner_set_daily_reward(p_amount numeric)
returns void language plpgsql security definer set search_path=public,pg_catalog as $$
begin
 if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
 if p_amount is null or p_amount<0 or p_amount>1000 then raise exception 'invalid_reward'; end if;
 insert into public.store_settings(setting_key,setting_value,updated_by) values('daily_reward_amount',p_amount::text,auth.uid())
 on conflict(setting_key) do update set setting_value=excluded.setting_value,updated_by=auth.uid(),updated_at=now();
end; $$;

create or replace function public.claim_daily_reward()
returns table(reward_amount numeric,new_balance numeric,claimed_date date)
language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_amount numeric(14,2); v_balance numeric(14,2); v_date date:=(timezone('Africa/Cairo',now()))::date;
begin
 if auth.uid() is null then raise exception 'login_required'; end if;
 select coalesce(nullif(setting_value,'')::numeric,5) into v_amount from public.store_settings where setting_key='daily_reward_amount';
 v_amount:=coalesce(v_amount,5); if v_amount<=0 then raise exception 'reward_disabled'; end if;
 insert into public.daily_reward_claims(user_id,claim_date,amount) values(auth.uid(),v_date,v_amount) on conflict(user_id,claim_date) do nothing;
 if not found then raise exception 'already_claimed_today'; end if;
 insert into public.wallets(user_id,balance) values(auth.uid(),0) on conflict(user_id) do nothing;
 update public.wallets set balance=balance+v_amount,updated_at=now() where user_id=auth.uid() returning balance into v_balance;
 insert into public.wallet_ledger(user_id,amount,balance_after,reason,entry_type,operator_id) values(auth.uid(),v_amount,v_balance,'مكافأة الدخول اليومية','daily_reward',null);
 return query select v_amount,v_balance,v_date;
end; $$;
revoke all on function public.owner_set_daily_reward(numeric) from public;
revoke all on function public.claim_daily_reward() from public;
grant execute on function public.owner_set_daily_reward(numeric) to authenticated;
grant execute on function public.claim_daily_reward() to authenticated;


-- =====================================================================
-- Included migration: supabase/daily_reward_streak.sql
-- =====================================================================

-- NEXORA daily attendance streak: day 1 = base reward (20 EGP), +5 EGP per consecutive day; missed day resets.
insert into public.store_settings(setting_key,setting_value)
values('daily_reward_amount','20')
on conflict(setting_key) do nothing;

create or replace function public.claim_daily_reward()
returns table(reward_amount numeric,new_balance numeric,claimed_date date)
language plpgsql security definer set search_path=public,pg_catalog as $$
declare
 v_amount numeric(14,2);
 v_base numeric(14,2);
 v_yesterday_amount numeric(14,2);
 v_balance numeric(14,2);
 v_date date:=(timezone('Africa/Cairo',now()))::date;
begin
 if auth.uid() is null then raise exception 'login_required'; end if;
 select coalesce(nullif(setting_value,'')::numeric,20) into v_base
 from public.store_settings where setting_key='daily_reward_amount';
 v_base:=coalesce(v_base,20);
 if v_base<=0 then raise exception 'reward_disabled'; end if;

 select amount into v_yesterday_amount
 from public.daily_reward_claims
 where user_id=auth.uid() and claim_date=v_date-1;
 if found then v_amount:=v_yesterday_amount+5; else v_amount:=v_base; end if;

 insert into public.daily_reward_claims(user_id,claim_date,amount)
 values(auth.uid(),v_date,v_amount) on conflict(user_id,claim_date) do nothing;
 if not found then raise exception 'already_claimed_today'; end if;

 insert into public.wallets(user_id,balance) values(auth.uid(),0)
 on conflict(user_id) do nothing;
 update public.wallets set balance=balance+v_amount,updated_at=now()
 where user_id=auth.uid() returning balance into v_balance;
 insert into public.wallet_ledger(user_id,amount,balance_after,reason,entry_type,operator_id)
 values(auth.uid(),v_amount,v_balance,'مكافأة الحضور اليومي','daily_reward',null);
 return query select v_amount,v_balance,v_date;
end; $$;


-- =====================================================================
-- Included migration: supabase/storefront.sql
-- =====================================================================

-- NEXORA storefront compatibility migration
-- Safe for the existing bigint products/orders/order_items tables.
-- No product seed data; no existing customer/order/wallet rows are deleted.

create extension if not exists pgcrypto;

-- Keep the existing products table and its rows. Add only storefront fields.
alter table public.products add column if not exists name text;
update public.products
set name = coalesce(nullif(btrim(name), ''), nullif(btrim(description), ''), 'منتج #' || id::text)
where name is null or btrim(name) = '';
alter table public.products alter column name set not null;
alter table public.products add column if not exists category text not null default 'عام';
alter table public.products add column if not exists old_price numeric(12,2) not null default 0;
alter table public.products add column if not exists image_url text not null default '';
alter table public.products add column if not exists stock integer not null default 0;
alter table public.products add column if not exists active boolean not null default true;
alter table public.products add column if not exists brand text not null default '';
alter table public.products add column if not exists updated_at timestamptz not null default now();

-- Extend the existing orders table instead of recreating it.
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists cancelled_by uuid references auth.users(id);
alter table public.orders add column if not exists payment_method text not null default 'wallet';
alter table public.orders add column if not exists sender_phone text;
alter table public.orders add column if not exists transfer_reference text;
alter table public.orders add column if not exists reviewed_at timestamptz;
alter table public.orders add column if not exists reviewed_by uuid references auth.users(id);
alter table public.orders add column if not exists review_note text;

-- Mark legacy Vodafone Cash orders correctly so wallet cancellation cannot refund them.
update public.orders
set payment_method = 'vodafone_cash'
where sender_phone is not null
  and status in ('pending_review','paid','rejected');

-- Preserve old statuses while allowing both existing Vodafone Cash orders and wallet orders.
do $$
declare v_status_att smallint;
declare c record;
begin
  select attnum into v_status_att
  from pg_attribute
  where attrelid='public.orders'::regclass and attname='status' and not attisdropped;
  for c in
    select conname
    from pg_constraint
    where conrelid='public.orders'::regclass
      and contype='c'
      and conkey=array[v_status_att]::smallint[]
  loop
    execute format('alter table public.orders drop constraint %I', c.conname);
  end loop;
  alter table public.orders
    add constraint nexora_orders_status_check
    check (status in ('pending_review','paid','rejected','placed','processing','shipped','completed','cancelled'));
end $$;

-- Existing order_items rows and foreign keys remain intact.
alter table public.order_items add column if not exists line_total numeric(12,2);
update public.order_items
set line_total = unit_price * quantity
where line_total is null;
alter table public.order_items alter column line_total set not null;

-- Favorites use the actual bigint product key.
create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id bigint not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

alter table public.products enable row level security;
alter table public.favorites enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "nexora_products_public_read" on public.products;
create policy "nexora_products_public_read" on public.products
for select to anon, authenticated
using (active or public.is_nexora_owner());

drop policy if exists "nexora_products_owner_write" on public.products;
create policy "nexora_products_owner_write" on public.products
for all to authenticated
using (public.is_nexora_owner())
with check (public.is_nexora_owner());

drop policy if exists "nexora_favorites_read" on public.favorites;
create policy "nexora_favorites_read" on public.favorites
for select to authenticated
using (user_id = auth.uid() or public.is_nexora_owner());

drop policy if exists "nexora_favorites_insert" on public.favorites;
create policy "nexora_favorites_insert" on public.favorites
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "nexora_favorites_delete" on public.favorites;
create policy "nexora_favorites_delete" on public.favorites
for delete to authenticated
using (user_id = auth.uid());

drop policy if exists "nexora_orders_read" on public.orders;
create policy "nexora_orders_read" on public.orders
for select to authenticated
using (user_id = auth.uid() or public.is_nexora_owner());

drop policy if exists "nexora_order_items_read" on public.order_items;
create policy "nexora_order_items_read" on public.order_items
for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.user_id = auth.uid() or public.is_nexora_owner())
  )
);

create or replace function public.place_wallet_order(p_items jsonb)
returns bigint
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_item record;
  v_product public.products%rowtype;
  v_total numeric(14,2) := 0;
  v_order_id bigint;
  v_balance numeric(14,2);
begin
  if auth.uid() is null then raise exception 'login_required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_items';
  end if;

  -- Aggregate duplicate cart lines before checking stock, preventing over-selling.
  for v_item in
    select (value->>'product_id')::bigint as product_id,
           sum((value->>'quantity')::integer)::integer as quantity
    from jsonb_array_elements(p_items)
    group by (value->>'product_id')::bigint
    order by (value->>'product_id')::bigint
  loop
    if v_item.quantity < 1 or v_item.quantity > 20 then
      raise exception 'invalid_quantity';
    end if;
    select * into v_product
    from public.products
    where id = v_item.product_id and active = true
    for update;
    if not found or v_product.stock < v_item.quantity then
      raise exception 'product_unavailable_or_out_of_stock';
    end if;
    v_total := v_total + (v_product.price * v_item.quantity);
  end loop;

  if v_total <= 0 then raise exception 'invalid_total'; end if;

  select balance into v_balance
  from public.wallets
  where user_id = auth.uid()
  for update;
  if not found then raise exception 'wallet_not_found'; end if;
  if v_balance < v_total then raise exception 'insufficient_balance'; end if;

  insert into public.orders(user_id, total, status, payment_method)
  values (auth.uid(), v_total, 'placed', 'wallet')
  returning id into v_order_id;

  for v_item in
    select (value->>'product_id')::bigint as product_id,
           sum((value->>'quantity')::integer)::integer as quantity
    from jsonb_array_elements(p_items)
    group by (value->>'product_id')::bigint
    order by (value->>'product_id')::bigint
  loop
    select * into v_product from public.products where id = v_item.product_id;
    insert into public.order_items(order_id, product_id, product_name, unit_price, quantity, line_total)
    values (v_order_id, v_product.id, v_product.name, v_product.price, v_item.quantity,
            v_product.price * v_item.quantity);
    update public.products
    set stock = stock - v_item.quantity, updated_at = now()
    where id = v_product.id;
  end loop;

  update public.wallets
  set balance = balance - v_total, updated_at = now()
  where user_id = auth.uid()
  returning balance into v_balance;

  insert into public.wallet_ledger(user_id, amount, balance_after, reason, entry_type, operator_id)
  values (auth.uid(), -v_total, v_balance, 'شراء طلب رقم #' || v_order_id, 'store_order', auth.uid());

  return v_order_id;
end;
$$;

create or replace function public.cancel_wallet_order(p_order_id bigint)
returns numeric
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_order public.orders%rowtype;
  v_balance numeric(14,2);
  v_line record;
begin
  if auth.uid() is null then raise exception 'login_required'; end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or (v_order.user_id <> auth.uid() and not public.is_nexora_owner()) then
    raise exception 'order_not_found';
  end if;
  if v_order.payment_method <> 'wallet' or v_order.status <> 'placed' then
    raise exception 'order_cannot_be_cancelled';
  end if;

  update public.orders
  set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid()
  where id = p_order_id;

  -- Restore stock for products that still exist.
  for v_line in
    select product_id, sum(quantity)::integer as quantity
    from public.order_items
    where order_id = p_order_id and product_id is not null
    group by product_id
  loop
    update public.products
    set stock = stock + v_line.quantity, updated_at = now()
    where id = v_line.product_id;
  end loop;

  update public.wallets
  set balance = balance + v_order.total, updated_at = now()
  where user_id = v_order.user_id
  returning balance into v_balance;
  if not found then raise exception 'wallet_not_found'; end if;

  insert into public.wallet_ledger(user_id, amount, balance_after, reason, entry_type, operator_id)
  values (v_order.user_id, v_order.total, v_balance,
          'استرجاع قيمة الطلب الملغي #' || p_order_id, 'order_refund', auth.uid());

  return v_balance;
end;
$$;

create or replace function public.owner_update_order_status(p_order_id bigint, p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  if p_status not in ('processing', 'shipped', 'completed') then
    raise exception 'invalid_status';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.payment_method <> 'wallet' then
    raise exception 'order_not_updatable';
  end if;

  if (v_order.status = 'placed' and p_status <> 'processing')
     or (v_order.status = 'processing' and p_status <> 'shipped')
     or (v_order.status = 'shipped' and p_status <> 'completed') then
    raise exception 'invalid_status_transition';
  end if;

  update public.orders set status = p_status where id = p_order_id;
end;
$$;


-- Vodafone Cash orders share the existing orders table without being mistaken for wallet purchases.
create or replace function public.place_vodafone_order(
  p_items jsonb,
  p_sender_phone text,
  p_transfer_reference text
)
returns table(order_id bigint, order_total numeric)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_item jsonb;
  v_name text;
  v_price numeric(14,2);
  v_qty integer;
  v_total numeric(14,2) := 0;
  v_order_id bigint;
begin
  if auth.uid() is null then raise exception 'login_required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 30 then
    raise exception 'cart_empty';
  end if;
  if length(regexp_replace(coalesce(p_sender_phone,''), '[^0-9]', '', 'g')) not between 10 and 15 then
    raise exception 'invalid_sender_phone';
  end if;
  if length(trim(coalesce(p_transfer_reference,''))) < 3 then
    raise exception 'transfer_reference_required';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_name := trim(v_item->>'product_name');
    v_price := (v_item->>'unit_price')::numeric;
    v_qty := (v_item->>'quantity')::integer;
    if v_name = '' or v_price <= 0 or v_qty < 1 or v_qty > 50 then
      raise exception 'invalid_items';
    end if;
    if not exists (
      select 1 from public.products p
      where p.name = v_name and p.active = true and p.price = v_price
    ) then
      raise exception 'product_price_changed_or_unavailable: %', v_name;
    end if;
    v_total := v_total + (v_price * v_qty);
  end loop;

  if v_total <= 0 then raise exception 'invalid_total'; end if;

  insert into public.orders(user_id,total,status,payment_method,sender_phone,transfer_reference)
  values(auth.uid(),v_total,'pending_review','vodafone_cash',trim(p_sender_phone),trim(p_transfer_reference))
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_name := trim(v_item->>'product_name');
    v_price := (v_item->>'unit_price')::numeric;
    v_qty := (v_item->>'quantity')::integer;
    insert into public.order_items(order_id,product_name,unit_price,quantity,line_total)
    values(v_order_id,v_name,v_price,v_qty,v_price*v_qty);
  end loop;

  return query select v_order_id,v_total;
end;
$$;

create or replace function public.owner_review_vodafone_order(
  p_order_id bigint,
  p_status text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_order public.orders%rowtype;
  v_line record;
  v_product public.products%rowtype;
begin
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  if p_status not in ('paid','rejected') then raise exception 'invalid_status'; end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.payment_method <> 'vodafone_cash' or v_order.status <> 'pending_review' then
    raise exception 'order_not_pending';
  end if;

  if p_status = 'paid' then
    for v_line in
      select id, product_name, unit_price, quantity
      from public.order_items
      where order_id = p_order_id
      order by id
      for update
    loop
      select * into v_product
      from public.products
      where name = v_line.product_name
        and price = v_line.unit_price
        and active = true
      order by id
      limit 1
      for update;

      if not found or v_product.stock < v_line.quantity then
        raise exception 'product_unavailable_or_out_of_stock: %', v_line.product_name;
      end if;

      update public.products
      set stock = stock - v_line.quantity, updated_at = now()
      where id = v_product.id;

      update public.order_items
      set product_id = v_product.id
      where id = v_line.id;
    end loop;
  end if;

  update public.orders
  set status = p_status,
      review_note = coalesce(p_note,''),
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_order_id;
end;
$$;

revoke all on function public.place_wallet_order(jsonb) from public;
revoke all on function public.cancel_wallet_order(bigint) from public;
revoke all on function public.owner_update_order_status(bigint,text) from public;
revoke all on function public.place_vodafone_order(jsonb,text,text) from public;
revoke all on function public.owner_review_vodafone_order(bigint,text,text) from public;
grant execute on function public.is_nexora_owner() to anon, authenticated;
grant execute on function public.place_wallet_order(jsonb) to authenticated;
grant execute on function public.cancel_wallet_order(bigint) to authenticated;
grant execute on function public.owner_update_order_status(bigint,text) to authenticated;
grant execute on function public.place_vodafone_order(jsonb,text,text) to authenticated;
grant execute on function public.owner_review_vodafone_order(bigint,text,text) to authenticated;

grant select on public.products to anon, authenticated;
grant select on public.favorites, public.orders, public.order_items to authenticated;
grant insert, delete on public.favorites to authenticated;
revoke insert, update, delete on public.orders, public.order_items from anon, authenticated;
