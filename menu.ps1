[console]::InputEncoding = [console]::OutputEncoding = [System.Text.Encoding]::UTF8

$UrlModuloBateria = "https://raw.githubusercontent.com/edmilsons2025/diagtools/main/modulo_bateria.ps1"

function Show-Menu {
    Clear-Host
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "           SISTEMA DE DIAGNOSTICO POSITIVO             "
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host " 1. [Coletas] - Bateria e Inventário"
    Write-Host " 2. [Testes]  - Em breve..."
    Write-Host " Q. Sair"
    Write-Host "-------------------------------------------------------"
}

do {
    Show-Menu
    $opcao = Read-Host "Selecione uma opção"

    switch ($opcao) {
        '1' { 
            Write-Host "Carregando módulo de Bateria da nuvem..." -ForegroundColor Gray
            
            # 1. Cria uma URL anti-cache para garantir que baixe sempre a versão mais nova
            $UrlAntiCache = "$UrlModuloBateria?v=$([guid]::NewGuid())"
            
            # 2. Faz o download do código
            $CodigoFonte = Invoke-RestMethod -Uri $UrlAntiCache
            
            # 3. Injeta o código na memória da forma correta (Ignora bugs de caracteres invisíveis/BOM)
            . ([ScriptBlock]::Create($CodigoFonte))
            
            # 4. Chama a função
            ExecutarColetaCompleta
        }
        '2' { Write-Host "Módulo em breve..."; Start-Sleep 2 }
        'q' { exit }
        default { Write-Host "Inválido"; Start-Sleep 1 }
    }
} while ($true)