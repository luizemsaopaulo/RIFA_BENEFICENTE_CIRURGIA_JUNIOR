-- ================================================================
-- RIFA DO JÚNIOR — CONFIGURAR / RECONFIGURAR LOGIN ADMIN
-- ================================================================
-- Usuário Supabase Auth informado:
-- 2056972b-35bc-4b4a-9f8e-7cb883ed5bed
--
-- Login do painel:
-- junior@gmail.com
--
-- Senha:
-- 123456
--
-- Este arquivo NÃO define o PIN de ações sensíveis.
-- Use JUNIOR_CONFIGURAR_PIN.sql para isso.
-- ================================================================

create schema if not exists private;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter table private.junior_admin_secret
  add column if not exists auth_user_id uuid;

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

delete from private.junior_admin_sessions;

select
  id,
  auth_user_id,
  email,
  updated_at
from private.junior_admin_secret
where id=1;
