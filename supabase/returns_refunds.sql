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
  -- Owner must physically receive and inspect the returned product before approving this action.
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
