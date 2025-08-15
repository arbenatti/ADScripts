# Script para Verificar Usuários Habilitados sem Login há mais de 3 meses
Write-Host "=== RELATÓRIO DE USUÁRIOS HABILITADOS SEM LOGIN HÁ MAIS DE 3 MESES ===" -ForegroundColor Cyan
Write-Host "Iniciando análise..." -ForegroundColor Green
Write-Host ""

# Parâmetros de configuração
$DataLimite = (Get-Date).AddMonths(-3)
$Resultados = @()
$UsuariosComLogin = @{}

Write-Host "[1/5] Identificando Domain Controllers..." -ForegroundColor Yellow
try {
    $DomainControllers = Get-ADDomainController -Filter * | Select-Object Name, Domain
    Write-Host "Encontrados $($DomainControllers.Count) DCs." -ForegroundColor Green
} catch {
    Write-Host "Erro ao buscar Domain Controllers: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/5] Buscando usuários HABILITADOS no AD..." -ForegroundColor Yellow
try {
    $UsuariosHabilitados = Get-ADUser -Filter {Enabled -eq $true} -Properties SamAccountName, Name, Department, Title, Description, LastLogonDate, WhenCreated, WhenChanged
    Write-Host "Total de usuários habilitados: $($UsuariosHabilitados.Count)" -ForegroundColor Green
} catch {
    Write-Host "Erro ao buscar usuários habilitados: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[3/5] Verificando último login em cada DC..." -ForegroundColor Yellow
$i = 0

foreach ($Usuario in $UsuariosHabilitados) {
    $i++
    $UltimoLogin = $null
    $DCOrigem = $null

    # Verificar em todos os DCs para encontrar o último login mais recente
    foreach ($DC in $DomainControllers) {
        try {
            $LogonData = Get-ADUser -Identity $Usuario.SamAccountName -Server $DC.Name -Properties LastLogon, LastLogonTimestamp -ErrorAction SilentlyContinue

            if ($LogonData) {
                # Verificar LastLogon (mais preciso)
                if ($LogonData.LastLogon -and $LogonData.LastLogon -gt 0) {
                    try {
                        $LoginDate = [DateTime]::FromFileTime($LogonData.LastLogon)
                        if (-not $UltimoLogin -or $LoginDate -gt $UltimoLogin) {
                            $UltimoLogin = $LoginDate
                            $DCOrigem = $DC.Name
                        }
                    } catch {
                        Write-Host "Erro ao converter LastLogon para $($Usuario.SamAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                # Fallback para LastLogonTimestamp
                elseif ($LogonData.LastLogonTimestamp -and $LogonData.LastLogonTimestamp -gt 0) {
                    try {
                        $LoginTimestamp = [DateTime]::FromFileTime($LogonData.LastLogonTimestamp)
                        if (-not $UltimoLogin -or $LoginTimestamp -gt $UltimoLogin) {
                            $UltimoLogin = $LoginTimestamp
                            $DCOrigem = $DC.Name
                        }
                    } catch {
                        Write-Host "Erro ao converter LastLogonTimestamp para $($Usuario.SamAccountName): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
        } catch {
            Write-Host "Erro ao consultar $($Usuario.SamAccountName) no DC $($DC.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Armazenar o último login encontrado
    if ($UltimoLogin -and $UltimoLogin -is [DateTime] -and $UltimoLogin -gt (Get-Date "1900-01-01")) {
        $UsuariosComLogin[$Usuario.SamAccountName] = @{
            UltimoLogin = $UltimoLogin
            DCOrigem    = $DCOrigem
            Usuario     = $Usuario
        }
    } else {
        # Para usuários sem login válido, considerar como "nunca logou"
        $UsuariosComLogin[$Usuario.SamAccountName] = @{
            UltimoLogin = $null
            DCOrigem    = "Nunca logou"
            Usuario     = $Usuario
        }
    }

    # Progresso
    if ($i % 100 -eq 0) { 
        Write-Host "Processados: $i/$($UsuariosHabilitados.Count) usuários..." -ForegroundColor Gray 
    }
}

Write-Host ""
Write-Host "[4/5] Identificando usuários sem login há mais de 3 meses..." -ForegroundColor Yellow

foreach ($Usuario in $UsuariosComLogin.Keys) {
    $InfoLogin = $UsuariosComLogin[$Usuario]
    $UltimoLogin = $InfoLogin.UltimoLogin
    $UsuarioObj = $InfoLogin.Usuario
    
    $DeveIncluir = $false
    $DiasAtras = "N/A"
    $StatusLogin = ""
    
    if ($UltimoLogin -and $UltimoLogin -is [DateTime]) {
        # Usuário tem data de login válida
        try {
            $DiasAtras = [math]::Round((Get-Date).Subtract($UltimoLogin).TotalDays, 0)
            
            if ($UltimoLogin -lt $DataLimite) {
                # Login há mais de 3 meses
                $DeveIncluir = $true
                $StatusLogin = "Login há mais de 3 meses"
            } else {
                # Login recente (menos de 3 meses) - não incluir
                $StatusLogin = "Login recente (menos de 3 meses)"
            }
        } catch {
            Write-Host "Erro ao calcular dias para usuário $Usuario : $($_.Exception.Message)" -ForegroundColor Yellow
            $DeveIncluir = $true
            $StatusLogin = "Erro no cálculo"
        }
    } else {
        # Usuário nunca fez login
        $DeveIncluir = $true
        $StatusLogin = "Nunca fez login"
        $DiasAtras = "Nunca"
    }
    
    # Incluir apenas usuários que atendem aos critérios
    if ($DeveIncluir) {
        $Resultados += [PSCustomObject]@{
            Nome         = $UsuarioObj.Name
            Login        = $Usuario
            UltimoLogin  = if ($UltimoLogin) { $UltimoLogin.ToString("dd/MM/yyyy HH:mm:ss") } else { "Nunca" }
            DiasAtras    = $DiasAtras
            DCOrigem     = $InfoLogin.DCOrigem
            Status       = "HABILITADO"
            StatusLogin  = $StatusLogin
            Departamento = if ($UsuarioObj.Department) { $UsuarioObj.Department } else { "N/A" }
            Cargo        = if ($UsuarioObj.Title) { $UsuarioObj.Title } else { "N/A" }
            DataCriacao  = if ($UsuarioObj.WhenCreated) { $UsuarioObj.WhenCreated.ToString("dd/MM/yyyy") } else { "N/A" }
            UltimaAlteracao = if ($UsuarioObj.WhenChanged) { $UsuarioObj.WhenChanged.ToString("dd/MM/yyyy") } else { "N/A" }
        }
    }
}

Write-Host ""
Write-Host "[5/5] Gerando relatório final..." -ForegroundColor Yellow

# Ordenar resultados por dias sem login (decrescente)
$Resultados = $Resultados | Sort-Object { 
    if ($_.DiasAtras -eq "Nunca") { 9999 } 
    elseif ($_.DiasAtras -eq "N/A") { 9998 } 
    else { [int]$_.DiasAtras } 
} -Descending

Write-Host ""
Write-Host "=== RESUMO ===" -ForegroundColor Cyan
Write-Host "Total de usuários habilitados analisados: $($UsuariosHabilitados.Count)" -ForegroundColor White
Write-Host "Usuários habilitados sem login há mais de 3 meses: $($Resultados.Count)" -ForegroundColor Yellow

# Estatísticas detalhadas
$NuncaLogou = ($Resultados | Where-Object { $_.StatusLogin -eq "Nunca fez login" }).Count
$LoginAntigo = ($Resultados | Where-Object { $_.StatusLogin -eq "Login há mais de 3 meses" }).Count

Write-Host "  - Nunca fizeram login: $NuncaLogou" -ForegroundColor Red
Write-Host "  - Login há mais de 3 meses: $LoginAntigo" -ForegroundColor Orange
Write-Host ""

# Exibir resultados
if ($Resultados.Count -gt 0) {
    Write-Host "=== USUÁRIOS HABILITADOS SEM LOGIN HÁ MAIS DE 3 MESES ===" -ForegroundColor Cyan
    $Resultados | Format-Table -AutoSize Nome, Login, UltimoLogin, DiasAtras, StatusLogin, Departamento, Cargo
    
    # Opção para exportar
    Write-Host ""
    $Exportar = Read-Host "Deseja exportar o relatório para CSV? (S/N)"
    if ($Exportar -eq "S" -or $Exportar -eq "s") {
        $NomeArquivo = "Usuarios_Habilitados_SemLogin_3meses_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $Resultados | Export-Csv -Path $NomeArquivo -Encoding UTF8 -NoTypeInformation -Delimiter ";"
        Write-Host "Relatório exportado para: $NomeArquivo" -ForegroundColor Green
    }
} else {
    Write-Host "Nenhum usuário habilitado encontrado sem login há mais de 3 meses." -ForegroundColor Green
}

Write-Host ""
Write-Host "Análise concluída!" -ForegroundColor Green
