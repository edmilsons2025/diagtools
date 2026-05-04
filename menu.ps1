[console]::InputEncoding = [console]::OutputEncoding = [System.Text.Encoding]::UTF8

# URL corrigida para o link RAW do GitHub
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
            
            # Baixa e injeta na memória
            Invoke-RestMethod -Uri $UrlModuloBateria | Invoke-Expression
            
            # Nome da função corrigido com os hifens
            ExecutarColetaCompleta
        }
        '2' { Write-Host "Módulo em breve..."; Start-Sleep 2 }
        'q' { exit }
        default { Write-Host "Inválido"; Start-Sleep 1 }
    }
} while ($true)