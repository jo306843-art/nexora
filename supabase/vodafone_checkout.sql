-- NEXORA Vodafone Cash checkout
create table if not exists public.store_catalog (
  product_name text primary key,
  price numeric(14,2) not null check(price > 0),
  active boolean not null default true
);
insert into public.store_catalog(product_name,price) values
('ساعة يد كلاسيكية',7600),('حقيبة جلد أنيقة',2800),('عطر فاخر',1850),
('سماعة لاسلكية',1250),('حذاء رياضي',1920),('نظارة شمسية',980),
('كرسي منزلي',3400),('ساعة ذكية',2200)
on conflict(product_name) do update set price=excluded.price;

create table if not exists public.orders (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete restrict,
 total numeric(14,2) not null check(total > 0),
 status text not null default 'pending_review' check(status in ('pending_review','paid','rejected','processing','shipped')),
 payment_method text not null default 'vodafone_cash' check(payment_method='vodafone_cash'),
 sender_phone text not null,
 transfer_reference text not null,
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id),
 review_note text
);
create table if not exists public.order_items (
 id bigint generated always as identity primary key,
 order_id bigint not null references public.orders(id) on delete cascade,
 product_name text not null,
 unit_price numeric(14,2) not null,
 quantity integer not null check(quantity between 1 and 50),
 line_total numeric(14,2) not null
);
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
drop policy if exists nx_orders_read on public.orders;
create policy nx_orders_read on public.orders for select to authenticated using(user_id=auth.uid() or public.is_nexora_owner());
drop policy if exists nx_order_items_read on public.order_items;
create policy nx_order_items_read on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_nexora_owner())));
grant select on public.orders,public.order_items to authenticated;
revoke insert,update,delete on public.orders,public.order_items from anon,authenticated;

create or replace function public.place_vodafone_order(p_items jsonb,p_sender_phone text,p_transfer_reference text)
returns table(order_id bigint,order_total numeric)
language plpgsql security definer set search_path=public,pg_catalog as $$
declare
 v_item jsonb; v_name text; v_price numeric(14,2); v_qty integer; v_total numeric(14,2):=0; v_order_id bigint;
begin
 if auth.uid() is null then raise exception 'login_required'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'cart_empty'; end if;
 if length(regexp_replace(coalesce(p_sender_phone,''),'[^0-9]','','g')) not between 10 and 15 then raise exception 'invalid_sender_phone'; end if;
 if length(trim(coalesce(p_transfer_reference,'')))<3 then raise exception 'transfer_reference_required'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_name:=trim(v_item->>'product_name'); v_price:=(v_item->>'unit_price')::numeric; v_qty:=(v_item->>'quantity')::integer;
   if v_qty<1 or v_qty>50 then raise exception 'invalid_quantity'; end if;
   if exists(select 1 from public.store_catalog c where c.product_name=v_name and c.active and c.price=v_price)
      or exists(select 1 from public.products p where p.name=v_name and p.active and p.price=v_price) then
      v_total:=v_total+(v_price*v_qty);
   else raise exception 'product_price_changed_or_unavailable: %',v_name;
   end if;
 end loop;
 insert into public.orders(user_id,total,sender_phone,transfer_reference)
 values(auth.uid(),v_total,trim(p_sender_phone),trim(p_transfer_reference)) returning id into v_order_id;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_name:=trim(v_item->>'product_name'); v_price:=(v_item->>'unit_price')::numeric; v_qty:=(v_item->>'quantity')::integer;
   insert into public.order_items(order_id,product_name,unit_price,quantity,line_total)
   values(v_order_id,v_name,v_price,v_qty,v_price*v_qty);
 end loop;
 return query select v_order_id,v_total;
end; $$;

create or replace function public.owner_review_vodafone_order(p_order_id bigint,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=public,pg_catalog as $$
begin
 if not public.is_nexora_owner() then raise exception 'owner_only'; end if;
 if p_status not in ('paid','rejected','processing','shipped') then raise exception 'invalid_status'; end if;
 update public.orders set status=p_status,review_note=coalesce(p_note,''),reviewed_at=now(),reviewed_by=auth.uid()
 where id=p_order_id and status='pending_review';
 if not found then raise exception 'order_not_pending'; end if;
end; $$;
revoke all on function public.place_vodafone_order(jsonb,text,text) from public;
revoke all on function public.owner_review_vodafone_order(bigint,text,text) from public;
grant execute on function public.place_vodafone_order(jsonb,text,text) to authenticated;
grant execute on function public.owner_review_vodafone_order(bigint,text,text) to authenticated;
