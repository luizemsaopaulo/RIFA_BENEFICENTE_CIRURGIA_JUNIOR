-- ================================================================
-- RIFA DO JÚNIOR — ATUALIZAÇÃO PARA QUANTIDADE CONFIGURÁVEL
-- Execute no MESMO projeto Supabase onde a rifa do Júnior já foi instalada.
-- Não altera objetos de outras rifas.
-- ================================================================

alter table public.junior_raffle_numbers drop constraint if exists junior_raffle_numbers_number_check;
alter table public.junior_raffle_numbers add constraint junior_raffle_numbers_number_check check (number >= 1);

create or replace function private.junior_begin_reservation(
  p_name text,p_whatsapp text,p_numbers integer[],p_provider text,p_expires_at timestamptz default null,
  p_cash_received_by text default null,p_cash_received_phone text default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_numbers integer[];v_id uuid:=gen_random_uuid();v_order_nsu text;v_total integer;v_amount integer;v_state public.junior_raffle_public_state%rowtype;
begin
  select * into v_state from public.junior_raffle_public_state where id=1 for update;
  if v_state.id is null then raise exception 'Estado da rifa não encontrado.'; end if;
  if v_state.sales_closed then raise exception 'As vendas desta rifa estão encerradas.'; end if;
  if v_state.draw_at is not null and now()>=v_state.draw_at then raise exception 'As vendas desta rifa estão encerradas.'; end if;
  if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_name,'')))>80 then raise exception 'Digite um nome válido.'; end if;
  if coalesce(p_whatsapp,'') !~ '^[0-9]{10,11}$' then raise exception 'Digite um WhatsApp válido com DDD.'; end if;
  if coalesce(cardinality(p_numbers),0)<1 then raise exception 'Escolha pelo menos um número.'; end if;
  if p_provider not in ('infinitepay','personal_pix','cash','manual') then raise exception 'Forma de pagamento inválida.'; end if;
  select array_agg(distinct x order by x) into v_numbers from unnest(p_numbers) x;
  if cardinality(v_numbers)<>cardinality(p_numbers) then raise exception 'Existem números repetidos na seleção.'; end if;
  if exists(select 1 from unnest(v_numbers) x where x<1 or x>v_state.total_numbers) then raise exception 'Seleção contém número fora da quantidade configurada para esta rifa.'; end if;
  perform n.number from public.junior_raffle_numbers n where n.number=any(v_numbers) order by n.number for update;
  select count(*) into v_total from public.junior_raffle_numbers n where n.number=any(v_numbers);
  if v_total<>cardinality(v_numbers) then raise exception 'Um ou mais números não existem.'; end if;
  if exists(select 1 from public.junior_raffle_numbers n where n.number=any(v_numbers) and n.status<>'available') then raise exception 'Um dos números escolhidos acabou de ficar indisponível.'; end if;
  v_order_nsu:='JUNIOR-'||replace(v_id::text,'-','');v_amount:=cardinality(v_numbers)*v_state.unit_price_cents;
  insert into public.junior_reservations(id,buyer_name,whatsapp,numbers,payment_status,order_nsu,expected_amount_cents,payment_provider,expires_at,cash_received_by,cash_received_phone)
    values(v_id,trim(p_name),p_whatsapp,v_numbers,'pending',v_order_nsu,v_amount,p_provider,p_expires_at,nullif(trim(coalesce(p_cash_received_by,'')),''),nullif(p_cash_received_phone,''));
  update public.junior_raffle_numbers set status='pending',updated_at=now() where number=any(v_numbers);
  return jsonb_build_object('ok',true,'order_id',v_id,'order_nsu',v_order_nsu,'amount_cents',v_amount,'numbers',to_jsonb(v_numbers),'expires_at',p_expires_at);
end;
$$;

create or replace function public.junior_admin_set_total_numbers_session(p_session_token text,p_total_numbers integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_state public.junior_raffle_public_state%rowtype;v_busy integer:=0;v_added integer:=0;v_removed integer:=0;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  if p_total_numbers is null or p_total_numbers<1 then raise exception 'A quantidade deve ser um número inteiro maior que zero.'; end if;
  select * into v_state from public.junior_raffle_public_state where id=1 for update;
  if v_state.id is null then raise exception 'Estado da rifa não encontrado.'; end if;
  if v_state.winner_number is not null then raise exception 'A quantidade não pode ser alterada após o sorteio oficial.'; end if;
  if p_total_numbers=v_state.total_numbers then return jsonb_build_object('ok',true,'old_total_numbers',v_state.total_numbers,'total_numbers',p_total_numbers,'added',0,'removed',0,'max_potential_cents',(p_total_numbers::bigint*v_state.unit_price_cents)); end if;
  if p_total_numbers>v_state.total_numbers then
    insert into public.junior_raffle_numbers(number,status) select n,'available' from generate_series(v_state.total_numbers+1,p_total_numbers) n on conflict (number) do nothing;
    get diagnostics v_added=row_count;
  else
    select count(*) into v_busy from public.junior_raffle_numbers where number>p_total_numbers and status<>'available';
    if v_busy>0 then raise exception 'Não é possível reduzir: existem % número(s) pendente(s) ou pago(s) acima do novo limite.',v_busy; end if;
    delete from public.junior_raffle_numbers where number>p_total_numbers and status='available';get diagnostics v_removed=row_count;
  end if;
  update public.junior_raffle_public_state set total_numbers=p_total_numbers,updated_at=now() where id=1;
  return jsonb_build_object('ok',true,'old_total_numbers',v_state.total_numbers,'total_numbers',p_total_numbers,'added',v_added,'removed',v_removed,'max_potential_cents',(p_total_numbers::bigint*v_state.unit_price_cents));
end;
$$;

revoke all on function private.junior_begin_reservation(text,text,integer[],text,timestamptz,text,text) from public;
grant execute on function private.junior_begin_reservation(text,text,integer[],text,timestamptz,text,text) to service_role;
revoke all on function public.junior_admin_set_total_numbers_session(text,integer) from public;
grant execute on function public.junior_admin_set_total_numbers_session(text,integer) to anon,authenticated;

-- Ajusta o sorteio para respeitar explicitamente a quantidade configurada.
create or replace function public.junior_admin_draw_winner_session(p_session_token text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_state public.junior_raffle_public_state%rowtype;v_number integer;v_res public.junior_reservations%rowtype;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  select * into v_state from public.junior_raffle_public_state where id=1 for update;
  if v_state.winner_number is not null then raise exception 'O sorteio oficial já foi realizado.'; end if;
  if v_state.draw_at is null then raise exception 'A data do sorteio ainda não foi configurada.'; end if;
  if now()<v_state.draw_at then raise exception 'O sorteio oficial ainda não foi liberado.'; end if;
  select number into v_number from public.junior_raffle_numbers where status='paid' and number<=v_state.total_numbers order by random() limit 1;
  if v_number is null then raise exception 'Não há número pago para sortear.'; end if;
  select * into v_res from public.junior_reservations where payment_status='paid' and v_number=any(numbers) order by paid_at nulls last,created_at limit 1;
  if v_res.id is null then raise exception 'Não foi possível localizar o comprador do número sorteado.'; end if;
  update public.junior_raffle_public_state set sales_closed=true,winner_number=v_number,winner_reservation_id=v_res.id,drawn_at=now(),updated_at=now() where id=1;
  return jsonb_build_object('number',v_number,'buyer_name',v_res.buyer_name,'whatsapp',v_res.whatsapp,'drawn_at',now());
end;
$$;
revoke all on function public.junior_admin_draw_winner_session(text) from public;
grant execute on function public.junior_admin_draw_winner_session(text) to anon,authenticated;
