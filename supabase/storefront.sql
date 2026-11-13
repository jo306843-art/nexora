-- NEXORA storefront: favorites + wallet-paid orders + safe cancellation/refunds
create extension if not exists pgcrypto;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'عام',
  price numeric(12,2) not null check (price > 0),
  old_price numeric(12,2) not null default 0,
  image_url text not null default '',
  stock integer not null default 0,
  active boolean not null default true,
  brand text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Compatibility for an existing catalog: add only missing fields; never replace product rows.
alter table public.products add column if not exists category text not null default 'عام';
alter table public.products add column if not exists old_price numeric(12,2) not null default 0;
alter table public.products add column if not exists image_url text not null default '';
alter table public.products add column if not exists stock integer not null default 0;
alter table public.products alter column stock set default 0;
alter table public.products add column if not exists brand text not null default '';
alter table public.products add column if not exists active boolean not null default true;
alter table public.products add column if not exists created_at timestamptz not null default now();
alter table public.products add column if not exists updated_at timestamptz not null default now();

create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, product_id)
);

create table if not exists public.orders (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete restrict,
  total numeric(12,2) not null check(total > 0),
  status text not null default 'placed'
    check(status in ('placed','processing','shipped','completed','cancelled')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id)
);
create table if not exists public.order_items (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(12,2) not null check(unit_price > 0),
  quantity integer not null check(quantity between 1 and 20),
  line_total numeric(12,2) not null check(line_total > 0)
);

alter table public.products enable row level security;
alter table public.favorites enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "nexora_products_public_read" on public.products;
create policy "nexora_products_public_read" on public.products for select to anon, authenticated using (active or public.is_nexora_owner());
drop policy if exists "nexora_products_owner_write" on public.products;
create policy "nexora_products_owner_write" on public.products for all to authenticated using (public.is_nexora_owner()) with check (public.is_nexora_owner());

drop policy if exists "nexora_favorites_read" on public.favorites;
create policy "nexora_favorites_read" on public.favorites for select to authenticated using (user_id=auth.uid() or public.is_nexora_owner());
drop policy if exists "nexora_favorites_insert" on public.favorites;
create policy "nexora_favorites_insert" on public.favorites for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "nexora_favorites_delete" on public.favorites;
create policy "nexora_favorites_delete" on public.favorites for delete to authenticated using (user_id=auth.uid());

drop policy if exists "nexora_orders_read" on public.orders;
create policy "nexora_orders_read" on public.orders for select to authenticated using (user_id=auth.uid() or public.is_nexora_owner());
drop policy if exists "nexora_order_items_read" on public.order_items;
create policy "nexora_order_items_read" on public.order_items for select to authenticated
using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_nexora_owner())));

create or replace function public.place_wallet_order(p_items jsonb)
returns bigint
language plpgsql
security definer
set search_path=public,pg_catalog
as $$
declare
  v_user uuid := auth.uid();
  v_item jsonb;
  v_product public.products%rowtype;
  v_total numeric(12,2) := 0;
  v_qty integer;
  v_order_id bigint;
  v_balance numeric(14,2);
begin
  if v_user is null then raise exception 'login_required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>30 then
    raise exception 'invalid_items';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 20 then raise exception 'invalid_quantity'; end if;
    select * into v_product from public.products
      where id=(v_item->>'product_id')::uuid and active=true for share;
    if not found then raise exception 'product_unavailable'; end if;
    v_total := v_total + v_product.price * v_qty;
  end loop;
  if v_total <= 0 then raise exception 'invalid_total'; end if;

  select balance into v_balance from public.wallets where user_id=v_user for update;
  if not found then raise exception 'wallet_not_found'; end if;
  if v_balance < v_total then raise exception 'insufficient_balance'; end if;

  insert into public.orders(user_id,total,status) values(v_user,v_total,'placed') returning id into v_order_id;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_product from public.products where id=(v_item->>'product_id')::uuid and active=true;
    insert into public.order_items(order_id,product_id,product_name,unit_price,quantity,line_total)
    values(v_order_id,v_product.id,v_product.name,v_product.price,v_qty,v_product.price*v_qty);
  end loop;

  update public.wallets set balance=balance-v_total,updated_at=now() where user_id=v_user returning balance into v_balance;
  insert into public.wallet_ledger(user_id,amount,balance_after,reason,entry_type,operator_id)
  values(v_user,-v_total,v_balance,'شراء طلب رقم #'||v_order_id,'store_order',v_user);
  return v_order_id;
end;
$$;

create or replace function public.cancel_wallet_order(p_order_id bigint)
returns numeric
language plpgsql
security definer
set search_path=public,pg_catalog
as $$
declare
  v_order public.orders%rowtype;
  v_balance numeric(14,2);
begin
  if auth.uid() is null then raise exception 'login_required'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or (v_order.user_id<>auth.uid() and not public.is_nexora_owner()) then raise exception 'order_not_found'; end if;
  if v_order.status<>'placed' then raise exception 'order_cannot_be_cancelled'; end if;

  update public.orders set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid() where id=p_order_id;
  update public.wallets set balance=balance+v_order.total,updated_at=now()
    where user_id=v_order.user_id returning balance into v_balance;
  insert into public.wallet_ledger(user_id,amount,balance_after,reason,entry_type,operator_id)
    values(v_order.user_id,v_order.total,v_balance,'استرجاع قيمة الطلب الملغي #'||p_order_id,'order_refund',auth.uid());
  return v_balance;
end;
$$;

create or replace function public.owner_update_order_status(p_order_id bigint,p_status text)
returns void
language plpgsql
security definer
set search_path=public,pg_catalog
as $$
declare v_order public.orders%rowtype;
begin
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  if p_status not in ('processing','shipped','completed') then raise exception 'invalid_status'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.status not in ('placed','processing','shipped') then raise exception 'order_not_updatable'; end if;
  if (v_order.status='placed' and p_status not in ('processing')) or
     (v_order.status='processing' and p_status not in ('shipped')) or
     (v_order.status='shipped' and p_status not in ('completed')) then
    raise exception 'invalid_status_transition';
  end if;
  update public.orders set status=p_status where id=p_order_id;
end;
$$;

revoke all on function public.place_wallet_order(jsonb) from public;
revoke all on function public.cancel_wallet_order(bigint) from public;
revoke all on function public.owner_update_order_status(bigint,text) from public;
grant execute on function public.is_nexora_owner() to anon,authenticated;
grant execute on function public.place_wallet_order(jsonb) to authenticated;
grant execute on function public.cancel_wallet_order(bigint) to authenticated;
grant execute on function public.owner_update_order_status(bigint,text) to authenticated;

revoke insert,update,delete on public.favorites,public.orders,public.order_items from anon,authenticated;
grant select on public.products to anon,authenticated;
grant select on public.favorites,public.orders,public.order_items to authenticated;
grant insert,delete on public.favorites to authenticated;

-- Seed 15 affordable gift and women's accessory products. Existing records are preserved.
insert into public.products(name,category,price,old_price,image_url,active)
select v.name,v.category,v.price,v.old_price,v.image_url,true
from (values
 ('طقم حلق وسلسلة ستانلس','إكسسوارات بناتي',180,250,'https://images.unsplash.com/photo-1611652022419-a9419f5f6e4c?w=700'),
 ('شنطة كروس صغيرة','شنط ومحافظ',450,550,'https://images.unsplash.com/photo-1584917865442-de89df76afd3?w=700'),
 ('نظارة شمس دائرية','إكسسوارات بناتي',300,400,'https://images.unsplash.com/photo-1511499767150-a48a237f0083?w=700'),
 ('مشبك شعر لؤلؤ','إكسسوارات بناتي',120,170,'https://images.unsplash.com/photo-1590548784585-643d2b9f2925?w=700'),
 ('طقم أساور رقيق','إكسسوارات بناتي',150,220,'https://images.unsplash.com/photo-1611591437281-460bfbe1220a?w=700'),
 ('محفظة نسائية صغيرة','شنط ومحافظ',250,330,'https://images.unsplash.com/photo-1627123424574-724758594e93?w=700'),
 ('ساعة كاجوال بسيطة','ساعات',500,650,'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=700'),
 ('حامل موبايل مكتبي','إكسسوارات موبايل',140,190,'https://images.unsplash.com/photo-1586953208448-b95a79798f07?w=700'),
 ('جراب موبايل أنيق','إكسسوارات موبايل',160,220,'https://images.unsplash.com/photo-1603313011108-4d2e6e6f4b9f?w=700'),
 ('مرآة مكياج صغيرة','جمال وعناية',130,180,'https://images.unsplash.com/photo-1583241800698-e8ab01830a6b?w=700'),
 ('فرش مكياج 5 قطع','جمال وعناية',220,300,'https://images.unsplash.com/photo-1512496015851-a90fb38ba796?w=700'),
 ('طقم توك شعر ملونة','إكسسوارات بناتي',100,150,'https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=700'),
 ('حافظة كروت أنيقة','شنط ومحافظ',190,260,'https://images.unsplash.com/photo-1622560480654-d96214fdc887?w=700'),
 ('سلسلة نظارة خفيفة','إكسسوارات بناتي',110,160,'https://images.unsplash.com/photo-1508296695146-257a814070b4?w=700'),
 ('إضاءة سيلفي للموبايل','إكسسوارات موبايل',280,360,'https://images.unsplash.com/photo-1512499617640-c74ae3a79d37?w=700')
) as v(name,category,price,old_price,image_url)
where not exists(select 1 from public.products p where p.name=v.name);

