[console]::InputEncoding = [console]::OutputEncoding = [System.Text.Encoding]::UTF8

# URLs dos módulos no GitHub (Links Raw)
$UrlModuloBateria = "https://gist.githubusercontent.com/.../raw/modulo_bateria.ps1"
# $UrlModuloTestes = "https://..."

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
    $input = Read-Host "Selecione uma opção"

    switch ($input) {
        '1' { 
            Write-Host "Carregando módulo local de Bateria..." -ForegroundColor Gray
            $CaminhoModulo = Join-Path -Path $PSScriptRoot -ChildPath "modulo_bateria.ps1"
            . $CaminhoModulo
            ExecutarColetaCompleta
        }
        '2' { Write-Host "Módulo em breve..."; Start-Sleep 2 }
        'q' { exit }
        default { Write-Host "Inválido"; Start-Sleep 1 }
    }
} while ($true)