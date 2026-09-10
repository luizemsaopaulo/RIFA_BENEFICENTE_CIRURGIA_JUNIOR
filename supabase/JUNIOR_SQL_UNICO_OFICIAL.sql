-- ============================================================================
-- RIFA BENEFICENTE DO JÚNIOR — SQL ÚNICO OFICIAL — BASE FINAL — 10/09/2026
-- ============================================================================
-- EXECUTE SOMENTE ESTE ARQUIVO: JUNIOR_SQL_UNICO_OFICIAL.sql, no projeto Supabase atual da rifa do Júnior.
-- Projeto esperado: rvwrljdjdogbcukxgguw
--
-- OBJETIVOS:
--   • alinhar frontend, RPCs e Edge Functions;
--   • corrigir o fluxo de dinheiro e garantir campos/funções necessários;
--   • preservar números, reservas, pagamentos, doações, foto e histórico;
--   • restaurar/garantir o login junior@gmail.com / 123456;
--   • manter o PIN existente (se ausente, inicializa 6253);
--   • instalar/garantir o suporte da foto pelo Admin.
--
-- NÃO HÁ DROP TABLE, TRUNCATE OU DELETE DE RESERVAS/NÚMEROS/PAGAMENTOS.
-- O único DROP é de constraints/policies conhecidas para recriá-las de forma
-- compatível; nenhum registro da rifa é removido.
-- ============================================================================

begin;
create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------
-- TABELAS PÚBLICAS DA RIFA DO JÚNIOR
-- ----------------------------------------------------------------
create table if not exists public.junior_raffle_numbers (
  number integer primary key check (number >= 1),
  status text not null default 'available' check (status in ('available','pending','paid')),
  updated_at timestamptz not null default now()
);

create table if not exists public.junior_reservations (
  id uuid primary key default extensions.gen_random_uuid(),
  buyer_name text not null,
  whatsapp text not null,
  numbers integer[] not null,
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','expired','cancelled')),
  order_nsu text not null unique,
  expected_amount_cents integer not null check (expected_amount_cents > 0),
  payment_provider text not null check (payment_provider in ('infinitepay','personal_pix','cash','manual')),
  checkout_url text,
  checkout_created_at timestamptz,
  expires_at timestamptz,
  paid_at timestamptz,
  payment_transaction_nsu text,
  payment_receipt_url text,
  capture_method text,
  personal_pix_contacted_at timestamptz,
  cash_received_by text,
  cash_received_phone text,
  confirmation_whatsapp_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.junior_raffle_public_state (
  id smallint primary key default 1 check (id = 1),
  sales_closed boolean not null default false,
  draw_at timestamptz,
  prize_text text,
  instagram_handle text,
  winner_number integer,
  winner_reservation_id uuid,
  drawn_at timestamptz,
  goal_cents integer not null default 1000000,
  unit_price_cents integer not null default 1000,
  total_numbers integer not null default 1000,
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------
-- TABELAS PRIVADAS EXCLUSIVAS DO JÚNIOR
-- ----------------------------------------------------------------
create table if not exists private.junior_admin_secret (
  id smallint primary key default 1 check (id = 1),
  auth_user_id uuid,
  email text not null,
  password_sha256 text not null,
  updated_at timestamptz not null default now()
);

alter table private.junior_admin_secret
  add column if not exists auth_user_id uuid;

create table if not exists private.junior_admin_sessions (
  token_sha256 text primary key,
  email text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists private.junior_admin_action_pin (
  id smallint primary key default 1 check (id = 1),
  pin_sha256 text not null,
  updated_at timestamptz not null default now()
);

create table if not exists private.junior_donations (
  id uuid primary key default extensions.gen_random_uuid(),
  amount_cents integer not null check (amount_cents > 0),
  note text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------
-- MIGRAÇÃO NÃO DESTRUTIVA PARA INSTALAÇÕES ANTERIORES
-- ----------------------------------------------------------------
-- CREATE TABLE IF NOT EXISTS não adiciona colunas que surgiram depois.
-- Estas instruções apenas completam o schema atual; não apagam dados.
alter table public.junior_reservations add column if not exists checkout_url text;
alter table public.junior_reservations add column if not exists checkout_created_at timestamptz;
alter table public.junior_reservations add column if not exists expires_at timestamptz;
alter table public.junior_reservations add column if not exists paid_at timestamptz;
alter table public.junior_reservations add column if not exists payment_transaction_nsu text;
alter table public.junior_reservations add column if not exists payment_receipt_url text;
alter table public.junior_reservations add column if not exists capture_method text;
alter table public.junior_reservations add column if not exists personal_pix_contacted_at timestamptz;
alter table public.junior_reservations add column if not exists cash_received_by text;
alter table public.junior_reservations add column if not exists cash_received_phone text;
alter table public.junior_reservations add column if not exists confirmation_whatsapp_sent_at timestamptz;
alter table public.junior_reservations add column if not exists updated_at timestamptz not null default now();

alter table public.junior_raffle_public_state add column if not exists sales_closed boolean not null default false;
alter table public.junior_raffle_public_state add column if not exists draw_at timestamptz;
alter table public.junior_raffle_public_state add column if not exists prize_text text;
alter table public.junior_raffle_public_state add column if not exists instagram_handle text;
alter table public.junior_raffle_public_state add column if not exists winner_number integer;
alter table public.junior_raffle_public_state add column if not exists winner_reservation_id uuid;
alter table public.junior_raffle_public_state add column if not exists drawn_at timestamptz;
alter table public.junior_raffle_public_state add column if not exists goal_cents integer not null default 1000000;
alter table public.junior_raffle_public_state add column if not exists unit_price_cents integer not null default 1000;
alter table public.junior_raffle_public_state add column if not exists total_numbers integer not null default 1000;
alter table public.junior_raffle_public_state add column if not exists beneficiary_photo_path text;
alter table public.junior_raffle_public_state add column if not exists updated_at timestamptz not null default now();

alter table private.junior_admin_secret add column if not exists auth_user_id uuid;
alter table private.junior_admin_secret add column if not exists updated_at timestamptz not null default now();
alter table private.junior_admin_sessions add column if not exists created_at timestamptz not null default now();
alter table private.junior_admin_sessions add column if not exists last_seen_at timestamptz not null default now();
alter table private.junior_admin_sessions add column if not exists expires_at timestamptz;
alter table private.junior_donations add column if not exists note text;
alter table private.junior_donations add column if not exists created_at timestamptz not null default now();

-- Garante que novas reservas aceitem as quatro formas atuais, sem apagar histórico.
alter table public.junior_reservations drop constraint if exists junior_reservations_payment_provider_check;
alter table public.junior_reservations
  add constraint junior_reservations_payment_provider_check
  check (payment_provider in ('infinitepay','personal_pix','cash','manual')) not valid;

comment on column public.junior_raffle_public_state.beneficiary_photo_path is
  'Caminho da foto ativa do Júnior no bucket junior-public-media; NULL usa placeholder.';

-- Estado da campanha. Em instalação nova começa com 1.000 como valor inicial,
-- mas a quantidade oficial é configurável pelo Admin e fica salva nesta tabela.
-- Em atualização de projeto já instalado, a quantidade existente NÃO é sobrescrita.
insert into public.junior_raffle_public_state(id,sales_closed,draw_at,prize_text,instagram_handle,goal_cents,unit_price_cents,total_numbers)
values (1,false,null,'R$ 200 no Pix',null,1000000,1000,1000)
on conflict (id) do nothing;

-- Configuração oficial atual. Preserva quantidade, sorteio, Instagram, vencedor e foto já existentes.
update public.junior_raffle_public_state
set prize_text='R$ 200 no Pix',
    goal_cents=1000000,
    unit_price_cents=1000,
    updated_at=now()
where id=1;

-- Remove a antiga trava fixa de 1..1000 caso esta seja uma atualização.
alter table public.junior_raffle_numbers drop constraint if exists junior_raffle_numbers_number_check;
alter table public.junior_raffle_numbers add constraint junior_raffle_numbers_number_check check (number >= 1);

-- Garante os números até a quantidade atualmente configurada, sem apagar dados.
insert into public.junior_raffle_numbers(number,status)
select n,'available' from generate_series(1,(select total_numbers from public.junior_raffle_public_state where id=1)) n
on conflict (number) do nothing;

-- Índices da base final (não alteram dados).
create index if not exists junior_raffle_numbers_status_idx on public.junior_raffle_numbers(status);
create index if not exists junior_reservations_status_created_idx on public.junior_reservations(payment_status,created_at desc);
create index if not exists junior_reservations_provider_status_idx on public.junior_reservations(payment_provider,payment_status);
create index if not exists junior_reservations_numbers_gin_idx on public.junior_reservations using gin(numbers);
create index if not exists junior_admin_sessions_expires_idx on private.junior_admin_sessions(expires_at);
create index if not exists junior_donations_created_idx on private.junior_donations(created_at desc);

-- Admin do Júnior já vinculado ao usuário informado no Supabase Authentication.
-- UUID Supabase Auth: 2056972b-35bc-4b4a-9f8e-7cb883ed5bed
-- Login do painel: junior@gmail.com
-- Senha administrativa definida pelo usuário: 123456
--
-- IMPORTANTE: a senha é armazenada somente como SHA-256 nesta tabela privada.
-- O PIN de 4 dígitos das ações sensíveis continua separado; se já existir é preservado, e em instalação sem PIN é inicializado como 6253.
insert into private.junior_admin_secret(id,auth_user_id,email,password_sha256)
values (
  1,
  '2056972b-35bc-4b4a-9f8e-7cb883ed5bed'::uuid,
  'junior@gmail.com',
  encode(extensions.digest('123456'::text,'sha256'),'hex')
)
on conflict (id) do update
set auth_user_id=excluded.auth_user_id,
    email=excluded.email,
    password_sha256=excluded.password_sha256,
    updated_at=now();

-- PIN administrativo: preserva o valor existente; se estiver ausente, inicializa 6253.
insert into private.junior_admin_action_pin(id,pin_sha256)
values (1,encode(extensions.digest('6253'::text,'sha256'),'hex'))
on conflict (id) do nothing;

-- ----------------------------------------------------------------
-- STORAGE DA FOTO DO JÚNIOR
-- ----------------------------------------------------------------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'junior-public-media','junior-public-media',true,8388608,
  array['image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do update
set public=excluded.public,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

-- ----------------------------------------------------------------
-- RLS / PERMISSÕES
-- ----------------------------------------------------------------
alter table public.junior_raffle_numbers enable row level security;
alter table public.junior_reservations enable row level security;
alter table public.junior_raffle_public_state enable row level security;
alter table private.junior_admin_secret enable row level security;
alter table private.junior_admin_sessions enable row level security;
alter table private.junior_admin_action_pin enable row level security;
alter table private.junior_donations enable row level security;

revoke all on public.junior_raffle_numbers from anon, authenticated;
revoke all on public.junior_reservations from anon, authenticated;
revoke all on public.junior_raffle_public_state from anon, authenticated;
revoke all on private.junior_admin_secret from public, anon, authenticated;
revoke all on private.junior_admin_sessions from public, anon, authenticated;
revoke all on private.junior_admin_action_pin from public, anon, authenticated;
revoke all on private.junior_donations from public, anon, authenticated;

grant select on public.junior_raffle_numbers to anon, authenticated;
grant select on public.junior_raffle_public_state to anon, authenticated;

drop policy if exists junior_public_read_numbers on public.junior_raffle_numbers;
create policy junior_public_read_numbers on public.junior_raffle_numbers for select to anon, authenticated using (true);

drop policy if exists junior_public_read_state on public.junior_raffle_public_state;
create policy junior_public_read_state on public.junior_raffle_public_state for select to anon, authenticated using (true);

-- ----------------------------------------------------------------
-- HELPERS PRIVADOS
-- ----------------------------------------------------------------
create or replace function private.junior_admin_credentials_ok(p_email text,p_password text)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,extensions
as $$
  select exists(
    select 1 from private.junior_admin_secret s
    where s.id=1
      and lower(s.email)=lower(trim(coalesce(p_email,'')))
      and s.password_sha256=encode(extensions.digest(coalesce(p_password,'')::text,'sha256'),'hex')
  );
$$;

create or replace function private.junior_action_pin_ok(p_pin text)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,extensions
as $$
  select exists(
    select 1 from private.junior_admin_action_pin p
    where p.id=1
      and p.pin_sha256=encode(extensions.digest(coalesce(p_pin,'')::text,'sha256'),'hex')
  );
$$;

create or replace function private.junior_admin_session_ok(p_session_token text)
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,extensions
as $$
declare v_hash text; v_ok boolean;
begin
  if coalesce(p_session_token,'')='' then return false; end if;
  delete from private.junior_admin_sessions where expires_at<=now();
  v_hash:=encode(extensions.digest(p_session_token::text,'sha256'),'hex');
  select exists(select 1 from private.junior_admin_sessions where token_sha256=v_hash and expires_at>now()) into v_ok;
  if v_ok then
    update private.junior_admin_sessions
      set last_seen_at=now(),expires_at=greatest(expires_at,now()+interval '30 days')
      where token_sha256=v_hash;
  end if;
  return v_ok;
end;
$$;

create or replace function private.junior_begin_reservation(
  p_name text,
  p_whatsapp text,
  p_numbers integer[],
  p_provider text,
  p_expires_at timestamptz default null,
  p_cash_received_by text default null,
  p_cash_received_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,extensions
as $$
declare
  v_numbers integer[];
  v_id uuid:=gen_random_uuid();
  v_order_nsu text;
  v_total integer;
  v_amount integer;
  v_state public.junior_raffle_public_state%rowtype;
begin
  select * into v_state from public.junior_raffle_public_state where id=1 for update;
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

  v_order_nsu:='JUNIOR-'||replace(v_id::text,'-','');
  v_amount:=cardinality(v_numbers)*v_state.unit_price_cents;

  insert into public.junior_reservations(
    id,buyer_name,whatsapp,numbers,payment_status,order_nsu,expected_amount_cents,payment_provider,
    expires_at,cash_received_by,cash_received_phone
  ) values (
    v_id,trim(p_name),p_whatsapp,v_numbers,'pending',v_order_nsu,v_amount,p_provider,
    p_expires_at,nullif(trim(coalesce(p_cash_received_by,'')),''),nullif(p_cash_received_phone,'')
  );

  update public.junior_raffle_numbers set status='pending',updated_at=now() where number=any(v_numbers);

  return jsonb_build_object('ok',true,'order_id',v_id,'order_nsu',v_order_nsu,'amount_cents',v_amount,'numbers',to_jsonb(v_numbers),'expires_at',p_expires_at);
end;
$$;

-- ----------------------------------------------------------------
-- FLUXOS DE PAGAMENTO (USADOS PELA EDGE FUNCTION)
-- ----------------------------------------------------------------
create or replace function public.junior_start_infinitepay_payment(p_name text,p_whatsapp text,p_numbers integer[])
returns jsonb language sql security definer set search_path=pg_catalog,extensions as $$
  select private.junior_begin_reservation(p_name,p_whatsapp,p_numbers,'infinitepay',now()+interval '2 hours',null,null);
$$;

create or replace function public.junior_start_personal_pix_payment(p_name text,p_whatsapp text,p_numbers integer[])
returns jsonb language sql security definer set search_path=pg_catalog,extensions as $$
  select private.junior_begin_reservation(p_name,p_whatsapp,p_numbers,'personal_pix',null,null,null);
$$;

create or replace function public.junior_start_cash_payment(p_name text,p_whatsapp text,p_numbers integer[],p_cash_received_by text,p_cash_received_phone text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
begin
  if length(trim(coalesce(p_cash_received_by,'')))<2 then raise exception 'Informe quem recebeu o dinheiro.'; end if;
  if coalesce(p_cash_received_phone,'') !~ '^[0-9]{10,11}$' then raise exception 'Telefone de quem recebeu o dinheiro é inválido.'; end if;
  return private.junior_begin_reservation(p_name,p_whatsapp,p_numbers,'cash',null,p_cash_received_by,p_cash_received_phone);
end;
$$;

create or replace function public.junior_personal_pix_contacted(p_order_nsu text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
begin
  update public.junior_reservations set personal_pix_contacted_at=now(),updated_at=now()
    where order_nsu=p_order_nsu and payment_provider='personal_pix';
  return jsonb_build_object('ok',found);
end;
$$;

create or replace function public.junior_payment_status(p_order_nsu text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype;
begin
  select * into r from public.junior_reservations where order_nsu=p_order_nsu;
  if r.id is null then return jsonb_build_object('found',false); end if;
  return jsonb_build_object('found',true,'payment_status',r.payment_status,'numbers',to_jsonb(r.numbers),'expected_amount_cents',r.expected_amount_cents,'checkout_url',r.checkout_url,'receipt_url',r.payment_receipt_url,'capture_method',r.capture_method,'paid_at',r.paid_at,'expires_at',r.expires_at);
end;
$$;

create or replace function public.junior_release_expired_pending()
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r record; v_count integer:=0;
begin
  for r in select id,numbers from public.junior_reservations where payment_status='pending' and expires_at is not null and expires_at<=now() for update
  loop
    update public.junior_raffle_numbers set status='available',updated_at=now() where number=any(r.numbers) and status='pending';
    update public.junior_reservations set payment_status='expired',updated_at=now() where id=r.id;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'released',v_count);
end;
$$;

create or replace function public.junior_cancel_infinitepay_pending(p_order_nsu text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype;
begin
  select * into r from public.junior_reservations where order_nsu=p_order_nsu for update;
  if r.id is null then return jsonb_build_object('ok',true,'found',false); end if;
  if r.payment_status='paid' then return jsonb_build_object('ok',false,'paid',true); end if;
  if r.payment_status='pending' then
    update public.junior_raffle_numbers set status='available',updated_at=now() where number=any(r.numbers) and status='pending';
    update public.junior_reservations set payment_status='cancelled',updated_at=now() where id=r.id;
  end if;
  return jsonb_build_object('ok',true,'found',true);
end;
$$;

create or replace function public.junior_confirm_infinitepay_payment(
  p_order_nsu text,p_transaction_nsu text,p_receipt_url text,p_capture_method text,p_amount_cents integer
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype;
begin
  select * into r from public.junior_reservations where order_nsu=p_order_nsu for update;
  if r.id is null then raise exception 'Pedido não encontrado.'; end if;
  if r.expected_amount_cents<>p_amount_cents then raise exception 'Valor do pagamento não corresponde ao pedido.'; end if;
  if r.payment_status='paid' then return jsonb_build_object('ok',true,'already_paid',true,'reservation_id',r.id); end if;
  if r.payment_status<>'pending' then raise exception 'Pedido não está pendente.'; end if;
  update public.junior_reservations set payment_status='paid',paid_at=now(),expires_at=null,payment_transaction_nsu=p_transaction_nsu,payment_receipt_url=nullif(p_receipt_url,''),capture_method=nullif(p_capture_method,''),updated_at=now() where id=r.id;
  update public.junior_raffle_numbers set status='paid',updated_at=now() where number=any(r.numbers);
  return jsonb_build_object('ok',true,'reservation_id',r.id,'numbers',to_jsonb(r.numbers));
end;
$$;

-- ----------------------------------------------------------------
-- LOGIN / SESSÃO ADMIN
-- ----------------------------------------------------------------
create or replace function public.junior_admin_login_session(p_email text,p_password text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_token text; v_hash text; v_expires timestamptz:=now()+interval '30 days';
begin
  if not private.junior_admin_credentials_ok(p_email,p_password) then raise exception 'E-mail ou senha incorretos.'; end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_hash:=encode(extensions.digest(v_token::text,'sha256'),'hex');
  insert into private.junior_admin_sessions(token_sha256,email,expires_at) values(v_hash,lower(trim(p_email)),v_expires);
  return jsonb_build_object('ok',true,'session_token',v_token,'expires_at',v_expires,'email',lower(trim(p_email)));
end;
$$;

create or replace function public.junior_admin_logout_session(p_session_token text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_hash text;
begin
  if coalesce(p_session_token,'')<>'' then
    v_hash:=encode(extensions.digest(p_session_token::text,'sha256'),'hex');
    delete from private.junior_admin_sessions where token_sha256=v_hash;
  end if;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.junior_admin_verify_action_pin_session(p_session_token text,p_pin text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
begin
  if not private.junior_admin_session_ok(p_session_token) then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',private.junior_action_pin_ok(p_pin));
end;
$$;

-- ----------------------------------------------------------------
-- DASHBOARD ADMIN
-- ----------------------------------------------------------------
create or replace function public.junior_admin_dashboard_session(p_session_token text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_state public.junior_raffle_public_state%rowtype; v_winner_name text; v_winner_whatsapp text;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  select * into v_state from public.junior_raffle_public_state where id=1;
  if v_state.winner_reservation_id is not null then select buyer_name,whatsapp into v_winner_name,v_winner_whatsapp from public.junior_reservations where id=v_state.winner_reservation_id; end if;
  return jsonb_build_object(
    'stats',jsonb_build_object(
      'available',(select count(*) from public.junior_raffle_numbers where status='available' and number<=v_state.total_numbers),
      'pending',(select count(*) from public.junior_raffle_numbers where status='pending' and number<=v_state.total_numbers),
      'paid',(select count(*) from public.junior_raffle_numbers where status='paid' and number<=v_state.total_numbers),
      'buyers',(select count(*) from public.junior_reservations where payment_status not in ('cancelled')),
      'donation_total_cents',coalesce((select sum(amount_cents) from private.junior_donations),0)
    ),
    'state',jsonb_build_object('sales_closed',v_state.sales_closed,'draw_at',v_state.draw_at,'prize_text',v_state.prize_text,'instagram_handle',v_state.instagram_handle,'winner_number',v_state.winner_number,'winner_name',v_winner_name,'winner_whatsapp',v_winner_whatsapp,'drawn_at',v_state.drawn_at,'goal_cents',v_state.goal_cents,'unit_price_cents',v_state.unit_price_cents,'total_numbers',v_state.total_numbers,'beneficiary_photo_path',v_state.beneficiary_photo_path),
    'numbers',coalesce((select jsonb_agg(jsonb_build_object('number',number,'status',status) order by number) from public.junior_raffle_numbers where number<=v_state.total_numbers),'[]'::jsonb),
    'reservations',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'buyer_name',buyer_name,'whatsapp',whatsapp,'numbers',to_jsonb(numbers),'payment_status',payment_status,
      'order_nsu',order_nsu,'expected_amount_cents',expected_amount_cents,'payment_provider',payment_provider,'checkout_url',checkout_url,
      'transaction_nsu',payment_transaction_nsu,'receipt_url',payment_receipt_url,'capture_method',capture_method,
      'expires_at',expires_at,'created_at',created_at,'paid_at',paid_at,'personal_pix_contacted_at',personal_pix_contacted_at,
      'cash_received_by',cash_received_by,'cash_received_phone',cash_received_phone,'confirmation_whatsapp_sent_at',confirmation_whatsapp_sent_at
    ) order by created_at desc) from public.junior_reservations),'[]'::jsonb),
    'donations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_cents',amount_cents,'note',note,'created_at',created_at) order by created_at desc) from private.junior_donations),'[]'::jsonb)
  );
end;
$$;

create or replace function public.junior_admin_set_payment_session(p_session_token text,p_reservation_id uuid,p_paid boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  select * into r from public.junior_reservations where id=p_reservation_id for update;
  if r.id is null then raise exception 'Pedido não encontrado.'; end if;
  if r.payment_status in ('expired','cancelled') then raise exception 'Reative o pedido antes de alterar o pagamento.'; end if;
  if p_paid then
    update public.junior_reservations set payment_status='paid',paid_at=coalesce(paid_at,now()),expires_at=null,updated_at=now() where id=r.id;
    update public.junior_raffle_numbers set status='paid',updated_at=now() where number=any(r.numbers);
  else
    update public.junior_reservations set payment_status='pending',paid_at=null,expires_at=null,updated_at=now() where id=r.id;
    update public.junior_raffle_numbers set status='pending',updated_at=now() where number=any(r.numbers);
  end if;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.junior_admin_cancel_reservation_session(p_session_token text,p_reservation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  select * into r from public.junior_reservations where id=p_reservation_id for update;
  if r.id is null then raise exception 'Pedido não encontrado.'; end if;
  update public.junior_raffle_numbers set status='available',updated_at=now() where number=any(r.numbers);
  update public.junior_reservations set payment_status='cancelled',updated_at=now() where id=r.id;
  return jsonb_build_object('ok',true,'numbers',to_jsonb(r.numbers));
end;
$$;

create or replace function public.junior_admin_reactivate_expired_session(p_session_token text,p_reservation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype; v_count integer;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  select * into r from public.junior_reservations where id=p_reservation_id for update;
  if r.id is null then raise exception 'Pedido não encontrado.'; end if;
  if r.payment_status not in ('expired','cancelled') then raise exception 'Esse pedido não precisa ser reativado.'; end if;
  perform number from public.junior_raffle_numbers where number=any(r.numbers) order by number for update;
  select count(*) into v_count from public.junior_raffle_numbers where number=any(r.numbers) and status='available';
  if v_count<>cardinality(r.numbers) then raise exception 'Um ou mais números já foram ocupados por outra pessoa.'; end if;
  update public.junior_raffle_numbers set status='pending',updated_at=now() where number=any(r.numbers);
  update public.junior_reservations set payment_status='pending',expires_at=null,updated_at=now() where id=r.id;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.junior_admin_create_reservation_session(p_session_token text,p_name text,p_whatsapp text,p_numbers integer[],p_paid boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v jsonb; v_id uuid;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  v:=private.junior_begin_reservation(p_name,p_whatsapp,p_numbers,'manual',null,null,null);
  v_id:=(v->>'order_id')::uuid;
  if p_paid then
    update public.junior_reservations set payment_status='paid',paid_at=now(),updated_at=now() where id=v_id;
    update public.junior_raffle_numbers set status='paid',updated_at=now() where number=any(p_numbers);
  end if;
  return v;
end;
$$;

create or replace function public.junior_admin_update_reservation_session(p_session_token text,p_reservation_id uuid,p_name text,p_whatsapp text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  if length(trim(coalesce(p_name,'')))<2 then raise exception 'Nome inválido.'; end if;
  if coalesce(p_whatsapp,'') !~ '^[0-9]{10,11}$' then raise exception 'WhatsApp inválido.'; end if;
  update public.junior_reservations set buyer_name=trim(p_name),whatsapp=p_whatsapp,updated_at=now() where id=p_reservation_id;
  if not found then raise exception 'Pedido não encontrado.'; end if;
  return jsonb_build_object('ok',true);
end;
$$;

create or replace function public.junior_admin_set_total_numbers_session(p_session_token text,p_total_numbers integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare
  v_state public.junior_raffle_public_state%rowtype;
  v_busy integer:=0;
  v_added integer:=0;
  v_removed integer:=0;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  if p_total_numbers is null or p_total_numbers<1 then raise exception 'A quantidade deve ser um número inteiro maior que zero.'; end if;

  -- O mesmo lock é usado no início das reservas, evitando compra concorrente durante a alteração.
  select * into v_state from public.junior_raffle_public_state where id=1 for update;
  if v_state.id is null then raise exception 'Estado da rifa não encontrado.'; end if;
  if v_state.winner_number is not null then raise exception 'A quantidade não pode ser alterada após o sorteio oficial.'; end if;
  if p_total_numbers=v_state.total_numbers then
    return jsonb_build_object('ok',true,'old_total_numbers',v_state.total_numbers,'total_numbers',p_total_numbers,'added',0,'removed',0,'max_potential_cents',(p_total_numbers::bigint*v_state.unit_price_cents));
  end if;

  if p_total_numbers>v_state.total_numbers then
    insert into public.junior_raffle_numbers(number,status)
      select n,'available' from generate_series(v_state.total_numbers+1,p_total_numbers) n
      on conflict (number) do nothing;
    get diagnostics v_added=row_count;
  else
    select count(*) into v_busy
      from public.junior_raffle_numbers
      where number>p_total_numbers and status<>'available';
    if v_busy>0 then
      raise exception 'Não é possível reduzir: existem % número(s) pendente(s) ou pago(s) acima do novo limite.',v_busy;
    end if;

    -- Não apaga reservas/histórico. Remove apenas linhas de números livres acima do novo limite.
    delete from public.junior_raffle_numbers where number>p_total_numbers and status='available';
    get diagnostics v_removed=row_count;
  end if;

  update public.junior_raffle_public_state set total_numbers=p_total_numbers,updated_at=now() where id=1;
  return jsonb_build_object('ok',true,'old_total_numbers',v_state.total_numbers,'total_numbers',p_total_numbers,'added',v_added,'removed',v_removed,'max_potential_cents',(p_total_numbers::bigint*v_state.unit_price_cents));
end;
$$;

create or replace function public.junior_admin_set_sales_closed_session(p_session_token text,p_closed boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  update public.junior_raffle_public_state set sales_closed=p_closed,updated_at=now() where id=1;
  return jsonb_build_object('ok',true,'sales_closed',p_closed);
end;
$$;

create or replace function public.junior_admin_add_donation_session(p_session_token text,p_amount_cents integer,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_id uuid:=gen_random_uuid();
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  if coalesce(p_amount_cents,0)<=0 then raise exception 'Valor inválido.'; end if;
  insert into private.junior_donations(id,amount_cents,note) values(v_id,p_amount_cents,nullif(trim(coalesce(p_note,'')),''));
  return jsonb_build_object('ok',true,'id',v_id);
end;
$$;

create or replace function public.junior_admin_delete_donation_session(p_session_token text,p_donation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  delete from private.junior_donations where id=p_donation_id;
  return jsonb_build_object('ok',found);
end;
$$;

create or replace function public.junior_admin_mark_confirmation_whatsapp_sent_session(p_session_token text,p_reservation_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare r public.junior_reservations%rowtype; v_sent timestamptz;
begin
  if not private.junior_admin_session_ok(p_session_token) then raise exception 'Sessão administrativa inválida ou expirada.'; end if;
  select * into r from public.junior_reservations where id=p_reservation_id for update;
  if r.id is null then raise exception 'Pedido não encontrado.'; end if;
  if r.payment_status<>'paid' then raise exception 'O pagamento ainda não está confirmado.'; end if;
  if r.confirmation_whatsapp_sent_at is not null then return jsonb_build_object('ok',true,'already_sent',true,'sent_at',r.confirmation_whatsapp_sent_at); end if;
  v_sent:=now();
  update public.junior_reservations set confirmation_whatsapp_sent_at=v_sent,updated_at=now() where id=r.id;
  return jsonb_build_object('ok',true,'already_sent',false,'sent_at',v_sent);
end;
$$;

create or replace function public.junior_admin_draw_winner_session(p_session_token text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,extensions as $$
declare v_state public.junior_raffle_public_state%rowtype; v_number integer; v_res public.junior_reservations%rowtype;
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

-- ----------------------------------------------------------------
-- VALIDADOR DA SESSÃO PARA A EDGE FUNCTION DA FOTO
-- ----------------------------------------------------------------
create or replace function public.junior_admin_media_session_validate(p_session_token text)
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,extensions
as $$
begin
  return private.junior_admin_session_ok(p_session_token);
end;
$$;

-- ----------------------------------------------------------------
-- BLOQUEIO / EXECUTE
-- ----------------------------------------------------------------
revoke all on function private.junior_admin_credentials_ok(text,text) from public;
revoke all on function private.junior_action_pin_ok(text) from public;
revoke all on function private.junior_admin_session_ok(text) from public;
revoke all on function private.junior_begin_reservation(text,text,integer[],text,timestamptz,text,text) from public;

grant execute on function private.junior_begin_reservation(text,text,integer[],text,timestamptz,text,text) to service_role;

-- Somente Edge/service_role pode iniciar e confirmar pagamentos.
revoke all on function public.junior_start_infinitepay_payment(text,text,integer[]) from public;
revoke all on function public.junior_start_personal_pix_payment(text,text,integer[]) from public;
revoke all on function public.junior_start_cash_payment(text,text,integer[],text,text) from public;
revoke all on function public.junior_personal_pix_contacted(text) from public;
revoke all on function public.junior_cancel_infinitepay_pending(text) from public;
revoke all on function public.junior_confirm_infinitepay_payment(text,text,text,text,integer) from public;
grant execute on function public.junior_start_infinitepay_payment(text,text,integer[]) to service_role;
grant execute on function public.junior_start_personal_pix_payment(text,text,integer[]) to service_role;
grant execute on function public.junior_start_cash_payment(text,text,integer[],text,text) to service_role;
grant execute on function public.junior_personal_pix_contacted(text) to service_role;
grant execute on function public.junior_cancel_infinitepay_pending(text) to service_role;
grant execute on function public.junior_confirm_infinitepay_payment(text,text,text,text,integer) to service_role;

-- Público pode consultar o próprio pedido e liberar expirados.
revoke all on function public.junior_payment_status(text) from public;
revoke all on function public.junior_release_expired_pending() from public;
grant execute on function public.junior_payment_status(text) to anon,authenticated;
grant execute on function public.junior_release_expired_pending() to anon,authenticated;

-- RPCs do Admin ficam acessíveis ao cliente, mas todos validam sessão internamente.
revoke all on function public.junior_admin_login_session(text,text) from public;
revoke all on function public.junior_admin_logout_session(text) from public;
revoke all on function public.junior_admin_verify_action_pin_session(text,text) from public;
revoke all on function public.junior_admin_dashboard_session(text) from public;
revoke all on function public.junior_admin_set_payment_session(text,uuid,boolean) from public;
revoke all on function public.junior_admin_cancel_reservation_session(text,uuid) from public;
revoke all on function public.junior_admin_reactivate_expired_session(text,uuid) from public;
revoke all on function public.junior_admin_create_reservation_session(text,text,text,integer[],boolean) from public;
revoke all on function public.junior_admin_update_reservation_session(text,uuid,text,text) from public;
revoke all on function public.junior_admin_set_total_numbers_session(text,integer) from public;
revoke all on function public.junior_admin_set_sales_closed_session(text,boolean) from public;
revoke all on function public.junior_admin_add_donation_session(text,integer,text) from public;
revoke all on function public.junior_admin_delete_donation_session(text,uuid) from public;
revoke all on function public.junior_admin_mark_confirmation_whatsapp_sent_session(text,uuid) from public;
revoke all on function public.junior_admin_draw_winner_session(text) from public;

grant execute on function public.junior_admin_login_session(text,text) to anon,authenticated;
grant execute on function public.junior_admin_logout_session(text) to anon,authenticated;
grant execute on function public.junior_admin_verify_action_pin_session(text,text) to anon,authenticated;
grant execute on function public.junior_admin_dashboard_session(text) to anon,authenticated;
grant execute on function public.junior_admin_set_payment_session(text,uuid,boolean) to anon,authenticated;
grant execute on function public.junior_admin_cancel_reservation_session(text,uuid) to anon,authenticated;
grant execute on function public.junior_admin_reactivate_expired_session(text,uuid) to anon,authenticated;
grant execute on function public.junior_admin_create_reservation_session(text,text,text,integer[],boolean) to anon,authenticated;
grant execute on function public.junior_admin_update_reservation_session(text,uuid,text,text) to anon,authenticated;
grant execute on function public.junior_admin_set_total_numbers_session(text,integer) to anon,authenticated;
grant execute on function public.junior_admin_set_sales_closed_session(text,boolean) to anon,authenticated;
grant execute on function public.junior_admin_add_donation_session(text,integer,text) to anon,authenticated;
grant execute on function public.junior_admin_delete_donation_session(text,uuid) to anon,authenticated;
grant execute on function public.junior_admin_mark_confirmation_whatsapp_sent_session(text,uuid) to anon,authenticated;
grant execute on function public.junior_admin_draw_winner_session(text) to anon,authenticated;

-- A Edge Function da foto usa service_role e valida a mesma sessão do painel.
revoke all on function public.junior_admin_media_session_validate(text) from public, anon, authenticated;
grant execute on function public.junior_admin_media_session_validate(text) to service_role;

-- FIM DA MIGRAÇÃO OFICIAL.
-- LOGIN: junior@gmail.com / senha 123456.
-- PIN: mantém o existente; se estiver ausente, cria 6253.


commit;

-- ============================================================================
-- AUTOCONFERÊNCIA SEM ALTERAR VENDAS
-- ============================================================================
select
  private.junior_admin_credentials_ok('junior@gmail.com','123456') as login_123456_ok,
  to_regprocedure('public.junior_admin_login_session(text,text)') is not null as rpc_login_ok,
  to_regprocedure('public.junior_admin_dashboard_session(text)') is not null as rpc_dashboard_ok,
  to_regprocedure('public.junior_start_cash_payment(text,text,integer[],text,text)') is not null as rpc_dinheiro_ok,
  to_regprocedure('public.junior_start_personal_pix_payment(text,text,integer[])') is not null as rpc_pix_pessoal_ok,
  to_regprocedure('public.junior_start_infinitepay_payment(text,text,integer[])') is not null as rpc_infinitepay_ok,
  to_regprocedure('public.junior_admin_media_session_validate(text)') is not null as rpc_foto_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='junior_reservations' and column_name='cash_received_by') as campo_recebedor_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='junior_reservations' and column_name='cash_received_phone') as campo_telefone_recebedor_ok,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='junior_raffle_public_state' and column_name='beneficiary_photo_path') as campo_foto_ok,
  exists(select 1 from storage.buckets where id='junior-public-media' and public=true) as bucket_foto_ok,
  (select prize_text='R$ 200 no Pix' and goal_cents=1000000 and unit_price_cents=1000 from public.junior_raffle_public_state where id=1) as configuracao_premio_meta_valor_ok,
  to_regprocedure('public.junior_admin_set_total_numbers_session(text,integer)') is not null as quantidade_configuravel_ok,
  to_regprocedure('public.junior_admin_draw_winner_session(text)') is not null as sorteio_oficial_ok;

-- Teste de sessão sem tocar em reservas: cria uma sessão de teste e a encerra.
do $$
declare
  v_login jsonb;
  v_token text;
  v_dash jsonb;
begin
  v_login := public.junior_admin_login_session('junior@gmail.com','123456');
  v_token := v_login->>'session_token';
  if coalesce(v_token,'')='' then raise exception 'AUTOTESTE: login não retornou token.'; end if;
  v_dash := public.junior_admin_dashboard_session(v_token);
  if v_dash is null then raise exception 'AUTOTESTE: dashboard não retornou dados.'; end if;
  if public.junior_admin_media_session_validate(v_token) is not true then raise exception 'AUTOTESTE: validador da foto rejeitou sessão válida.'; end if;
  perform public.junior_admin_logout_session(v_token);
  raise notice 'AUTOTESTE OK: login -> dashboard -> validador da foto -> logout.';
end;
$$;
