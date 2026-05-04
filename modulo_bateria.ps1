function ExecutarColetaCompleta {
    Clear-Host
    
    # Ajuste: Força o salvamento na raiz do C: (C:\)
    $WORKDIR = "C:\"

    $bios = Get-CimInstance -ClassName Win32_BIOS
    $SN = $bios.SerialNumber
    if ([string]::IsNullOrWhiteSpace($SN)) { $SN = $env:COMPUTERNAME }
    $SN = $SN -replace '[\\/:*?"<>|]', '_'
    $SN = $SN.Trim()

    $TS = Get-Date -Format 'yyyyMMdd_HHmmss'
    $FolderName = "Log_Diag_${SN}_${TS}"
    $TempFolder = Join-Path -Path $WORKDIR -ChildPath $FolderName
    
    $MD = Join-Path -Path $TempFolder -ChildPath "Relatorio_Completo_${SN}.md"
    $JSON = Join-Path -Path $TempFolder -ChildPath "Dados_Estruturados_${SN}.json"
    $EVTX = Join-Path -Path $TempFolder -ChildPath "SystemLog_${SN}.evtx"
    $DRIVERS = Join-Path -Path $TempFolder -ChildPath "Drivers_${SN}.csv"

    # Cria a pasta na raiz do C:
    New-Item -ItemType Directory -Path $TempFolder -Force | Out-Null

    Write-Host '=== ENGENHARIA DE SERVIÇOS: COLETA COMPLETA ===' -ForegroundColor Yellow
    Write-Host "Equipamento: $SN" -ForegroundColor Magenta
    Write-Host "Salvando dados em: $TempFolder" -ForegroundColor Gray
    Write-Host ''

    # --- 1. COLETA DE INVENTÁRIO, SO E AUDITORIA OEM ---
    Write-Host '[1/6] Coletando Inventário de Hardware, SO e Auditoria OEM...' -ForegroundColor Cyan
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $mbInfo = Get-CimInstance -ClassName Win32_BaseBoard
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $ramInfo = Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
    $ramTotalGB = [math]::Round(($ramInfo.Sum / 1GB), 2)
    
    # Novas coletas de hardware
    $gpuInfo = Get-CimInstance -ClassName Win32_VideoController
    $diskInfo = Get-CimInstance -ClassName Win32_DiskDrive
    $logicalDisks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
    $netInfo = Get-CimInstance -ClassName Win32_NetworkAdapter -Filter "PhysicalAdapter=True and NetConnectionStatus=2" -ErrorAction SilentlyContinue
    
    $hotfixes = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending

    $installDate = $osInfo.InstallDate.ToString('dd/MM/yyyy HH:mm:ss')
    $lastBoot = $osInfo.LastBootUpTime.ToString('dd/MM/yyyy HH:mm:ss')

    # Auditoria OEM (Pastas e Licença)
    $oemFolders = @('C:\OEM', 'C:\Recovery\OEM', 'C:\Drivers', 'C:\Windows\OEM')
    $foundOemFolders = @()
    foreach ($folder in $oemFolders) {
        if (Test-Path $folder) { $foundOemFolders += $folder }
    }
    
    $folderAuditResult = if ($foundOemFolders.Count -gt 0) { 
        "Encontradas: " + ($foundOemFolders -join ', ') 
    }
    else { 
        "Nenhuma pasta OEM detectada (Possível formatação Limpa)" 
    }

    $licInfo = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.ApplicationId -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } | Select-Object -First 1
    $licChannel = if ($licInfo) { $licInfo.Description } else { "Desconhecido" }
    
    $oemStatus = "Retail/Limpa (Suspeito)"
    if ($licChannel -match 'OEM' -or $osInfo.Manufacturer -match 'Positivo') {
        $oemStatus = "Original de Fábrica (Confirmado)"
    }

    # --- 2. COLETA DE BATERIA ---
    Write-Host '[2/6] Gerando Relatórios ACPI (PowerCfg)...' -ForegroundColor Cyan
    $argBattery = "/batteryreport /output `"$TempFolder\battery-report_$SN.html`""
    $argEnergy = "/energy /output `"$TempFolder\energy-report_$SN.html`" /duration 5"

    $p1 = Start-Process -FilePath 'powercfg' -ArgumentList $argBattery -PassThru -WindowStyle Hidden
    $p2 = Start-Process -FilePath 'powercfg' -ArgumentList $argEnergy -PassThru -WindowStyle Hidden

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (($p1.HasExited -eq $false -or $p2.HasExited -eq $false) -and $sw.Elapsed.TotalSeconds -lt 20) {
        Start-Sleep -Milliseconds 500
    }

    $p1_Status = if ($p1.HasExited) { 'OK' } else { Stop-Process -Id $p1.Id -Force; 'TIMEOUT' }
    $p2_Status = if ($p2.HasExited) { 'OK' } else { Stop-Process -Id $p2.Id -Force; 'TIMEOUT' }

    # --- 3. COLETA DE EVTX E HISTÓRICO ---
    Write-Host '[3/6] Analisando histórico temporal e Logs (EVTX)...' -ForegroundColor Cyan
    wevtutil epl System "$EVTX" /overwrite:true
    
    $sysEvents = Get-WinEvent -LogName System -ErrorAction SilentlyContinue | Select-Object TimeCreated
    $primeiroLog = "Desconhecido"
    $maiorGap = 0

    if ($sysEvents -and $sysEvents.Count -gt 1) {
        $primeiroLog = $sysEvents[-1].TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')
        $maxDiff = 0
        for ($i = 0; $i -lt $sysEvents.Count - 1; $i++) {
            $diff = ($sysEvents[$i].TimeCreated - $sysEvents[$i + 1].TimeCreated).TotalDays
            if ($diff -gt $maxDiff) { $maxDiff = $diff }
        }
        $maiorGap = [math]::Round($maxDiff, 1)
    }
    elseif ($sysEvents -and $sysEvents.Count -eq 1) {
        $primeiroLog = $sysEvents[0].TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')
    }

    # --- 4. COLETA DE DRIVERS ---
    Write-Host '[4/6] Exportando lista completa de Drivers...' -ForegroundColor Cyan
    driverquery /v /fo csv | Out-File -FilePath $DRIVERS -Encoding UTF8

    # --- FUNÇÕES DE FORMATAÇÃO E PARSER ---
    function Add-StructuredData {
        param([string]$Title, $Data, [string[]]$KeyProperties)
        $Block = "`n### $Title`n"
        if ($null -eq $Data -or $Data.Count -eq 0) {
            $Block += "[ERRO] Nenhum dado retornado pelo hardware para esta classe.`n"
        }
        else {
            $Block += "| Propriedade | Valor |`n"
            $Block += "| --- | --- |`n"
            foreach ($prop in $KeyProperties) {
                $value = if ($Data.PSObject.Properties.Match($prop)) { $Data.$prop } else { 'N/A' }
                $Block += "| $prop | $value |`n"
            }
            $Block += "`n"
        }
        [System.IO.File]::AppendAllText($MD, $Block, [System.Text.Encoding]::UTF8)
    }

    function Add-RawData {
        param([string]$Title, $Data)
        $Block = "`n#### Dados Brutos - $Title`n"
        $Block += '```text' + "`n"
        if ($null -eq $Data) {
            $Block += "[ERRO] Nenhum dado retornado pelo hardware para esta classe.`n"
        }
        else {
            $RawString = $Data | Format-List * | Out-String
            $Block += $RawString.Trim() + "`n"
        }
        $Block += '```' + "`n"
        [System.IO.File]::AppendAllText($MD, $Block, [System.Text.Encoding]::UTF8)
    }

    function Parse-BatteryReport {
        param([string]$ReportPath)
        if (-not (Test-Path $ReportPath)) { return $null }

        $html = Get-Content $ReportPath -Raw
        $parsed = [PSCustomObject]@{
            Fabricante                 = "Desconhecido"
            Modelo                     = "Desconhecido"
            DesignCapacity             = 0
            FullChargeCapacity         = 0
            CycleCount                 = 0
            HealthPercentage           = 0
            CapacidadeInicialHistorico = 0
            FalsosPositivosBMS         = 0
            AlertaDegradacao           = "Não"
        }

        if ($html -match 'MANUFACTURER</span></td><td>([^<]+)') { $parsed.Fabricante = $matches[1].Trim() }
        if ($html -match 'NAME</span></td><td>([^<]+)') { $parsed.Modelo = $matches[1].Trim() }
        
        if ($html -match 'Design Capacity.*?(\d[\d\.,]*)\s*mWh') { $parsed.DesignCapacity = [int]($matches[1] -replace '[\.,]', '') }
        if ($html -match 'Full Charge Capacity.*?(\d[\d\.,]*)\s*mWh') { $parsed.FullChargeCapacity = [int]($matches[1] -replace '[\.,]', '') }
        
        if ($html -match 'CYCLE COUNT</span></td><td>\s*(\d+)\s*<') { 
            $parsed.CycleCount = [int]$matches[1] 
        }
        else {
            $parsed.CycleCount = 0
        }
        
        if ($parsed.DesignCapacity -gt 0 -and $parsed.FullChargeCapacity -gt 0) {
            $parsed.HealthPercentage = [math]::Round(($parsed.FullChargeCapacity / $parsed.DesignCapacity) * 100, 2)
        }

        $parsed.FalsosPositivosBMS = [regex]::Matches($html, 'class="nullValue">-').Count

        $capacidades = [regex]::Matches($html, '(\d{1,2}[\.,]\d{3})\s*mWh')
        if ($capacidades.Count -gt 2) {
            $primeiraCapacidade = $capacidades[2].Groups[1].Value -replace '[\.,]', ''
            $parsed.CapacidadeInicialHistorico = [int]$primeiraCapacidade

            if ($parsed.FullChargeCapacity -lt ($parsed.CapacidadeInicialHistorico * 0.95) -and $parsed.CycleCount -lt 20) {
                $parsed.AlertaDegradacao = "Risco de Estufamento (Degradação Severa com Baixa Ciclagem)"
            }
            if ($parsed.FalsosPositivosBMS -gt 30) {
                $parsed.AlertaDegradacao += " | Alerta de BMS (Equipamento muito tempo inativo ou viciado na tomada)"
            }
        }
        return $parsed
    }

    # --- 5. CONSTRUÇÃO DO MARKDOWN ---
    Write-Host '[5/6] Construindo Relatório Markdown e Estruturas...' -ForegroundColor Cyan

    $mdBody = "# Relatório de Diagnóstico de Engenharia Completo`n`n"
    $mdBody += "- **Data/Hora do Diagnóstico:** $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))`n"
    $mdBody += "- **Serial Number (BIOS):** $SN`n"
    $mdBody += "- **Hostname:** $($env:COMPUTERNAME)`n"
    $mdBody += "---`n`n"

    $mdBody += "## 1. Inventário de Sistema e Hardware`n`n"
    $mdBody += "### Sistema Operacional e Integridade OEM`n"
    $mdBody += "| Propriedade | Valor |`n| --- | --- |`n"
    $mdBody += "| **Versão do SO** | $($osInfo.Caption) ($($osInfo.OSArchitecture))`n"
    $mdBody += "| **Build** | $($osInfo.BuildNumber)`n"
    $mdBody += "| **Data de Instalação (Build Atual)** | $installDate`n"
    $mdBody += "| **Último Boot (Tempo de Atividade)** | $lastBoot`n"
    $mdBody += "| **Data do Primeiro Log no Sistema** | $primeiroLog`n"
    $mdBody += "| **Canal de Licença (WMI)** | $licChannel`n"
    $mdBody += "| **Rastros de Pastas de Fábrica** | $folderAuditResult`n"
    $mdBody += "| **Diagnóstico OEM** | **$oemStatus**`n`n"

    $mdBody += "### Hardware Central`n"
    $gpuNames = if ($gpuInfo) { ($gpuInfo.Name) -join " e " } else { "N/A" }
    $mdBody += "| Propriedade | Valor |`n| --- | --- |`n"
    $mdBody += "| **Placa-mãe (Modelo/Fabricante)** | $($mbInfo.Product) / $($mbInfo.Manufacturer)`n"
    $mdBody += "| **Processador** | $($cpuInfo.Name)`n"
    $mdBody += "| **Placa(s) de Vídeo (GPU)** | $gpuNames`n"
    $mdBody += "| **Memória RAM Total** | $ramTotalGB GB`n`n"

    $mdBody += "### Discos Físicos`n"
    $mdBody += "| Modelo | Tipo | Tamanho (GB) |`n| --- | --- | --- |`n"
    foreach ($disk in $diskInfo) {
        $diskSize = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { "N/A" }
        $mdBody += "| $($disk.Model) | $($disk.MediaType) | $diskSize |`n"
    }
    $mdBody += "`n"

    $mdBody += "### Partições Lógicas (Espaço em Disco)`n"
    $mdBody += "| Unidade | Tamanho Total (GB) | Espaço Livre (GB) | % Livre |`n| --- | --- | --- | --- |`n"
    foreach ($vol in $logicalDisks) {
        $volSize = if ($vol.Size) { [math]::Round($vol.Size / 1GB, 2) } else { 0 }
        $volFree = if ($vol.FreeSpace) { [math]::Round($vol.FreeSpace / 1GB, 2) } else { 0 }
        $volPct = if ($volSize -gt 0) { [math]::Round(($volFree / $volSize) * 100, 1) } else { 0 }
        $mdBody += "| $($vol.DeviceID) | $volSize | $volFree | $volPct% |`n"
    }
    $mdBody += "`n"

    $mdBody += "### Interfaces de Rede Ativas`n"
    $mdBody += "| Nome do Adaptador | MAC Address | Status |`n| --- | --- | --- |`n"
    if ($netInfo) {
        foreach ($net in $netInfo) {
            $mdBody += "| $($net.Name) | $($net.MACAddress) | Conectado |`n"
        }
    }
    else {
        $mdBody += "| N/A | N/A | Nenhuma rede ativa encontrada |`n"
    }
    $mdBody += "`n---`n`n"

    $mdBody += "## 2. Últimas Atualizações Críticas (HotFixes)`n`n"
    $mdBody += "| ID da Atualização | Data de Instalação | Descrição |`n| --- | --- | --- |`n"
    $count = 0
    if ($hotfixes) {
        foreach ($hf in $hotfixes) {
            if ($count -ge 5) { break }
            $hfDate = if ($hf.InstalledOn) { $hf.InstalledOn.ToString('dd/MM/yyyy') } else { "N/A" }
            $mdBody += "| $($hf.HotFixID) | $hfDate | $($hf.Description) |`n"
            $count++
        }
    }
    else {
        $mdBody += "| N/A | N/A | Nenhum HotFix detectado. |`n"
    }
    $mdBody += "`n*(A lista de drivers foi exportada para o arquivo CSV na pasta).*`n`n---`n`n"

    $mdBody += "## 3. Diagnóstico de Energia e BMS`n"
    $mdBody += "| Métrica Forense | Resultado |`n| :--- | :--- |`n"
    $mdBody += "| **Maior Intervalo Desligado (Deep Discharge)** | $maiorGap dias consecutivos |`n"
    $mdBody += "| **Status PowerCfg Battery** | $p1_Status |`n"
    $mdBody += "| **Status PowerCfg Energy** | $p2_Status |`n`n"

    [System.IO.File]::WriteAllText($MD, $mdBody, [System.Text.Encoding]::UTF8)

    $win32Battery = Get-CimInstance -ClassName Win32_Battery
    $batteryStatus = Get-WmiObject -Class BatteryStatus -Namespace root\wmi -ErrorAction SilentlyContinue
    $batteryStatic = Get-WmiObject -Class BatteryStaticData -Namespace root\wmi -ErrorAction SilentlyContinue

    $parsedReport = Parse-BatteryReport -ReportPath "$TempFolder\battery-report_$SN.html"
    if ($parsedReport) {
        Add-StructuredData -Title 'Inteligência do Relatório HTML (BMS)' -Data $parsedReport -KeyProperties @('Fabricante', 'Modelo', 'DesignCapacity', 'FullChargeCapacity', 'CapacidadeInicialHistorico', 'CycleCount', 'HealthPercentage', 'FalsosPositivosBMS', 'AlertaDegradacao')
    }

    # CORREÇÃO: Dados Brutos restaurados e chamados corretamente
    [System.IO.File]::AppendAllText($MD, "`n---`n`n## 4. Dados Brutos de Hardware (BMS)`n", [System.Text.Encoding]::UTF8)
    Add-RawData -Title 'Win32_Battery' -Data $win32Battery
    Add-RawData -Title 'BatteryStatus' -Data $batteryStatus
    Add-RawData -Title 'BatteryStaticData' -Data $batteryStatic
    
    $mdLogs = "`n---`n`n## 5. Relatórios de Eventos do Sistema (Energia e Bateria)`n*(Nota: O arquivo .evtx completo está anexado para análise profunda).*`n"
    [System.IO.File]::AppendAllText($MD, $mdLogs, [System.Text.Encoding]::UTF8)

    $activeScheme = powercfg /getactivescheme | Out-String
    $schemeBlock = "`n### Plano de Energia Ativo`n"
    $schemeBlock += '```text' + "`n"
    $schemeBlock += $activeScheme.Trim() + "`n"
    $schemeBlock += '
```' + "`n"
    [System.IO.File]::AppendAllText($MD, $schemeBlock, [System.Text.Encoding]::UTF8)

    $events = Get-WinEvent -FilterHashtable @{LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power', 'Microsoft-Windows-Battery', 'Microsoft-Windows-Power-Troubleshooter' } -MaxEvents 50 -ErrorAction SilentlyContinue
    $evtBlock = "`n### Últimos 50 Eventos Críticos`n| Data/Hora | ID | Nível | Mensagem |`n| --- | --- | --- | --- |`n"
    if ($events) {
        foreach ($evt in $events) {
            $time = $evt.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')
            $id = $evt.Id
            $level = $evt.LevelDisplayName
            $msg = $evt.Message -replace "`n", " " -replace "`r", " "
            if ($msg.Length -gt 100) { $msg = $msg.Substring(0, 100) + "..." }
            $evtBlock += "| $time | $id | $level | $msg |`n"
        }
    }
    else {
        $evtBlock += "| N/A | N/A | N/A | Nenhum evento relacionado encontrado. |`n"
    }
    $evtBlock += "`n"
    [System.IO.File]::AppendAllText($MD, $evtBlock, [System.Text.Encoding]::UTF8)

    # --- 6. GERAÇÃO DO JSON ---
    Write-Host '[6/6] Gerando Arquivo JSON Estruturado e finalizando...' -ForegroundColor Cyan

    $structuredData = [PSCustomObject]@{
        Timestamp       = [DateTime]::Now
        SerialNumber    = $SN
        Hostname        = $env:COMPUTERNAME
        SystemInventory = [PSCustomObject]@{
            OS          = $osInfo.Caption
            Build       = $osInfo.BuildNumber
            InstallDate = $installDate
            Motherboard = $mbInfo.Product
            CPU         = $cpuInfo.Name
            GPU         = $gpuNames
            RAM_GB      = $ramTotalGB
            Disks       = $logicalDisks | Select-Object DeviceID, Size, FreeSpace
            Network     = $netInfo | Select-Object Name, MACAddress
            OEM_Audit   = [PSCustomObject]@{
                LicenseChannel = $licChannel
                FoldersFound   = $folderAuditResult
                Status         = $oemStatus
            }
        }
        UsageHistory    = [PSCustomObject]@{
            FirstLogDate = $primeiroLog
            LastBoot     = $lastBoot
            MaxIdleDays  = $maiorGap
        }
        PowerCfgStatus  = [PSCustomObject]@{
            BatteryReport = $p1_Status
            EnergyReport  = $p2_Status
        }
        BatteryData     = [PSCustomObject]@{
            Win32_Battery     = $win32Battery
            BatteryStatus     = $batteryStatus
            BatteryStaticData = $batteryStatic
            ParsedReport      = $parsedReport
        }
    }

    $structuredData | ConvertTo-Json -Depth 5 | Out-File $JSON -Encoding UTF8

    $mdFooter = "`n---`n### Diagnóstico de Alertas`n"
    $mdFooter += "* **Deep Discharge**: Valores acima de 30 dias inativos ($maiorGap detectados) frequentemente causam a oxidação do anodo de lítio, justificando o estufamento mesmo com poucos ciclos.`n"
    $mdFooter += "* **Falso Positivo de Ciclos**: Se a tag *AlertaDegradacao* apontar problemas com baixa ciclagem, o BMS corrompeu a contagem.`n"
    [System.IO.File]::AppendAllText($MD, $mdFooter, [System.Text.Encoding]::UTF8)

    Write-Host ''
    Write-Host '=== SUCESSO: RELATÓRIO CONCLUÍDO ===' -ForegroundColor Green
    Write-Host "Pasta gerada em: $TempFolder" -ForegroundColor Gray
    
    # Abre o Windows Explorer diretamente na pasta criada
    Start-Process "explorer.exe" $TempFolder
    
    Write-Host "`nPressione qualquer tecla para voltar ao menu..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}