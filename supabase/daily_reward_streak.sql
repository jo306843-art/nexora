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
