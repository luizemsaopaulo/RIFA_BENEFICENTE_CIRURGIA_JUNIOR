@echo off
setlocal
cd /d "%~dp0"
echo.
echo EDGE FUNCTION - FOTO DO JUNIOR PELO ADMIN
echo Funcao: junior-admin-media
echo Projeto: rvwrljdjdogbcukxgguw
echo.
echo Antes de publicar, execute no SQL Editor:
echo supabase\JUNIOR_ATUALIZAR_FOTO_ADMIN.sql
echo.
echo Este BAT exige Supabase CLI autenticado e projeto vinculado ao ref correto.
echo Se preferir, publique pelo Dashboard copiando:
echo supabase\functions\junior-admin-media\index.ts
echo.
supabase functions deploy junior-admin-media --no-verify-jwt --project-ref rvwrljdjdogbcukxgguw
pause
