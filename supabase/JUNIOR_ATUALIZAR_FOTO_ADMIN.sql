-- ============================================================================
-- RIFA DO JÚNIOR — ATUALIZAÇÃO ÚNICA: FOTO DO BENEFICIÁRIO PELO PAINEL ADM
-- Execute este arquivo UMA VEZ no SQL Editor do MESMO projeto Supabase da rifa.
-- Não altera dados das rifas Bruna/Juliana e não recria objetos existentes.
-- ============================================================================

begin;

-- 1) Caminho da foto ativa. NULL = usar o placeholder local do site.
alter table public.junior_raffle_public_state
  add column if not exists beneficiary_photo_path text;

comment on column public.junior_raffle_public_state.beneficiary_photo_path is
  'Caminho da foto ativa do Júnior no bucket junior-public-media; NULL usa placeholder.';

-- 2) Bucket público apenas para mídia pública da rifa do Júnior.
-- Upload/remoção NÃO são liberados para anon/authenticated; a Edge Function usa service_role.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'junior-public-media',
  'junior-public-media',
  true,
  8388608,
  array['image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- 3) Validador exclusivo da Edge Function.
-- Reaproveita a MESMA sessão administrativa já usada pelo painel atual.
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

revoke all on function public.junior_admin_media_session_validate(text) from public, anon, authenticated;
grant execute on function public.junior_admin_media_session_validate(text) to service_role;

commit;

-- Conferência simples: deve retornar uma linha com o bucket e a coluna instalada.
select
  exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='junior_raffle_public_state'
      and column_name='beneficiary_photo_path'
  ) as campo_foto_instalado,
  exists(
    select 1 from storage.buckets where id='junior-public-media'
  ) as bucket_foto_instalado;
