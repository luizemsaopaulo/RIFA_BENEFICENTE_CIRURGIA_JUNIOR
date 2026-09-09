@echo off
setlocal
cd /d "%~dp0"
echo.
echo EDGE FUNCTION DA RIFA DO JUNIOR
echo Funcao: junior-infinitepay-gateway
echo InfinitePay: $antonio-junior-zzc
echo.
echo Este BAT exige Supabase CLI autenticado.
echo Se preferir, publique pelo Dashboard do Supabase copiando o arquivo:
echo supabase\functions\junior-infinitepay-gateway\index.ts
echo.
supabase functions deploy junior-infinitepay-gateway --no-verify-jwt
pause
