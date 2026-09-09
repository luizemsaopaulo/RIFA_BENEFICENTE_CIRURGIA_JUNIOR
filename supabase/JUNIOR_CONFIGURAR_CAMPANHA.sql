-- ================================================================
-- CONFIGURAÇÕES QUE AINDA NÃO FORAM DEFINIDAS
-- ================================================================
-- Edite os valores abaixo SOMENTE quando decidir prêmio, data e Instagram.
-- Não é necessário executar este arquivo agora.
-- ================================================================

-- EXEMPLO: defina a data/hora do sorteio em horário de São Paulo.
-- update public.junior_raffle_public_state
-- set draw_at = '2026-12-20 20:00:00-03'::timestamptz,
--     updated_at = now()
-- where id = 1;

-- EXEMPLO: defina o prêmio.
-- update public.junior_raffle_public_state
-- set prize_text = 'DESCREVA O PRÊMIO AQUI', updated_at = now()
-- where id = 1;

-- EXEMPLO: defina o Instagram do sorteio/atualizações.
-- update public.junior_raffle_public_state
-- set instagram_handle = '@PERFIL', updated_at = now()
-- where id = 1;

-- IMPORTANTE:
-- também atualize js/config.js para que a página pública exiba os mesmos dados.


-- A QUANTIDADE DE NÚMEROS NÃO PRECISA SER EDITADA AQUI.
-- Use o Admin > Configuração da rifa > Quantidade total de números.
-- A alteração chama junior_admin_set_total_numbers_session e é protegida pelo PIN.
