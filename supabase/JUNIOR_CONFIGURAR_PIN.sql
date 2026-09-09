-- ================================================================
-- RIFA DO JÚNIOR — CONFIGURAR PIN DE 4 DÍGITOS
-- ================================================================
-- TROQUE SOMENTE: COLOQUE_O_PIN_AQUI
-- Exemplo de formato: 1234
-- ================================================================

do $$
declare
  v_pin text := 'COLOQUE_O_PIN_AQUI';
begin
  if v_pin = 'COLOQUE_O_PIN_AQUI' or v_pin !~ '^[0-9]{4}$' then
    raise exception 'Informe um PIN de exatamente 4 dígitos antes de executar.';
  end if;

  update private.junior_admin_action_pin
  set pin_sha256=encode(extensions.digest(v_pin::text,'sha256'),'hex'),
      updated_at=now()
  where id=1;

  delete from private.junior_admin_sessions;
end $$;
