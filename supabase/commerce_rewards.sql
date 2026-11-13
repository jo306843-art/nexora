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
