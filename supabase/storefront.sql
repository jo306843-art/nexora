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

create or replace function public.owner_refund_returned_wallet_order(p_order_id bigint)
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
  if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.payment_method <> 'wallet' or v_order.status <> 'completed' then
    raise exception 'order_not_returnable';
  end if;
  -- The owner confirms physical receipt and inspection before this one-time refund.
  update public.orders set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid()
  where id = p_order_id;
  for v_line in
    select product_id, sum(quantity)::integer as quantity
    from public.order_items where order_id = p_order_id and product_id is not null
    group by product_id
  loop
    update public.products set stock = stock + v_line.quantity, updated_at = now()
    where id = v_line.product_id;
  end loop;
  update public.wallets set balance = balance + v_order.total, updated_at = now()
  where user_id = v_order.user_id returning balance into v_balance;
  if not found then raise exception 'wallet_not_found'; end if;
  insert into public.wallet_ledger(user_id, amount, balance_after, reason, entry_type, operator_id)
  values (v_order.user_id, v_order.total, v_balance,
          'استرداد قيمة مرتجع الطلب #' || p_order_id, 'order_refund', auth.uid());
  return v_balance;
end;
$$;

revoke all on function public.owner_refund_returned_wallet_order(bigint) from public;
grant execute on function public.owner_refund_returned_wallet_order(bigint) to authenticated;
