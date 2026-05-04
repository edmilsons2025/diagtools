@echo off
chcp 65001 >nul
set "PS_FILE=%~dp0menu.ps1"

:: 1. Verifica privilegios de Administrador
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :run_script
) else (
    echo [INFO] Solicitando privilegios de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:run_script
:: 2. Executa o PS1 ignorando politicas de execucao
echo [INFO] Iniciando telemetria de bateria...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_FILE%"

:: 3. Segura a tela se o PowerShell fechar por erro inesperado
if %errorLevel% neq 0 (
    echo.
    echo [ERRO] Ocorreu uma falha na execucao do script.
    pause
)
exit /b