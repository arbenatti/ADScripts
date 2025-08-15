# =============================================
# SCRIPT ATUALIZADO: USUÁRIOS HABILITADOS COM LOGIN NOS ÚLTIMOS 3 MESES
# - Filtra apenas usuários habilitados (Enabled = $true)
# - Exclui contas de serviço e máquinas
# - Verifica logins históricos + sessões ativas
# =============================================

Import-Module ActiveDirectory

# Configurações
$DataLimite = (Get-Date).AddMonths(-3)
$Resultados = @()
$UsuariosComLogin = @{}

# 1. Obter todos os Domain Controllers
Write-Host "[1/4] Identificando Domain Controllers..." -ForegroundColor Cyan
$DomainControllers = Get-ADDomainController -Filter * | Sort-Object Name
Write-Host "Encontrados $($DomainControllers.Count) DCs." -ForegroundColor Green

# 2. Buscar SOMENTE usuários habilitados (filtro estrito)
Write-Host "`n[2/4] Buscando usuários HABILITADOS no AD..." -ForegroundColor Cyan
$UsuariosHabilitados = Get-ADUser -Filter {
        Enabled -eq $true -and 
        ObjectClass -eq "user"
    } -Properties Name, SamAccountName, LastLogonDate, DistinguishedName, Department, Title, Description, WhenCreated

Write-Host "Total de usuários habilitados: $($UsuariosHabilitados.Count)" -ForegroundColor Green

# 3. Verificar último login em TODOS os DCs
Write-Host "`n[3/4] Verificando último login em cada DC..." -ForegroundColor Cyan
$i = 0

foreach ($Usuario in $UsuariosHabilitados) {
    $i++
    $UltimoLogin = $null
    $DCOrigem = $null

    foreach ($DC in $DomainControllers) {
        try {
            $LogonData = Get-ADUser -Identity $Usuario.SamAccountName `
                -Server $DC.Name `
                -Properties LastLogon, LastLogonTimestamp `
                -ErrorAction SilentlyContinue

            if ($LogonData) {
                # Converter LastLogon (FileTime) para DateTime
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

    # Armazenar o último login encontrado APENAS se for válido
    if ($UltimoLogin -and $UltimoLogin -is [DateTime] -and $UltimoLogin -gt (Get-Date "1900-01-01")) {
        $UsuariosComLogin[$Usuario.SamAccountName] = @{
            UltimoLogin = $UltimoLogin
            DCOrigem    = $DCOrigem
        }
    } else {
        # Log para usuários sem data válida
        Write-Host "Usuário $($Usuario.SamAccountName) não possui data de login válida." -ForegroundColor Gray
    }


    # Progresso
    if ($i % 100 -eq 0) { Write-Host "Processados: $i/$($UsuariosHabilitados.Count) usuários..." -ForegroundColor Gray }
}

# Calcular dias atrás corretamente
# Adicionar usuários com login nos últimos 3 meses
foreach ($Usuario in $UsuariosComLogin.Keys) {
    $InfoLogin = $UsuariosComLogin[$Usuario]
    $UltimoLogin = $InfoLogin.UltimoLogin
    
    # Validar se UltimoLogin é uma data válida
    if ($UltimoLogin -and $UltimoLogin -is [DateTime]) {
        try {
            # Verificar se está dentro do período de 3 meses
            if ($UltimoLogin -ge $DataLimite) {
                # Calcular dias de forma segura
                $DiasAtras = [math]::Round((Get-Date).Subtract($UltimoLogin).TotalDays, 0)
                
                # Buscar informações adicionais do usuário
                $UsuarioInfo = Get-ADUser $Usuario -Properties Name, Department, Title, Description -ErrorAction SilentlyContinue
                
                $Resultados += [PSCustomObject]@{
                    Nome        = if ($UsuarioInfo) { $UsuarioInfo.Name } else { $Usuario }
                    Login       = $Usuario
                    UltimoLogin = $UltimoLogin.ToString("dd/MM/yyyy HH:mm:ss")
                    DiasAtras   = $DiasAtras
                    DCOrigem    = $InfoLogin.DCOrigem
                    Status      = "Login nos últimos 3 meses"
                    Departamento = if ($UsuarioInfo) { $UsuarioInfo.Department } else { "N/A" }
                    Cargo       = if ($UsuarioInfo) { $UsuarioInfo.Title } else { "N/A" }
                }
            }
        } catch {
            Write-Host "Erro ao processar usuário $Usuario : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Data inválida para usuário $Usuario - UltimoLogin: $UltimoLogin" -ForegroundColor Yellow
    }
}


# 5. Combinar resultados (logins históricos + sessões ativas)
Write-Host "`n[5/5] Gerando relatório final (somente usuários habilitados)..." -ForegroundColor Cyan

# Adicionar usuários com login nos últimos 3 meses
foreach ($Usuario in $UsuariosComLogin.Keys) {
    $UltimoLogin = $UsuariosComLogin[$Usuario].UltimoLogin
    if ($UltimoLogin -ge $DataLimite) {
        $Resultados += [PSCustomObject]@{
            Nome          = (Get-ADUser $Usuario -Properties Name).Name
            Login         = $Usuario
            UltimoLogin   = $UltimoLogin
            DCOrigem      = $UsuariosComLogin[$Usuario].DCOrigem
            Status        = "Histórico"
            Computador    = "N/A"
        }
    }
}

# Adicionar usuários com sessões ATIVAS (mesmo sem LastLogon recente)
foreach ($Sessao in $SessoesAtivas) {
    $Usuario = $Sessao.Usuario
    $Existente = $Resultados | Where-Object { $_.Login -eq $Usuario }

    if (-not $Existente) {
        $Resultados += [PSCustomObject]@{
            Nome          = (Get-ADUser $Usuario -Properties Name).Name
            Login         = $Usuario
            UltimoLogin   = $Sessao.HorarioLogin
            DCOrigem      = "Sessão Ativa"
            Status        = "LOGADO AGORA"
            Computador    = $Sessao.Computador
        }
    }
}

# 6. Exibir resultados (somente usuários habilitados)
if ($Resultados.Count -gt 0) {
    Write-Host "`n=== USUÁRIOS HABILITADOS COM LOGIN NOS ÚLTIMOS 3 MESES ===" -ForegroundColor Green
    Write-Host "Total: $($Resultados.Count) usuários" -ForegroundColor Green
    Write-Host ""

    # Ordenar por data de login (mais recente primeiro)
    $Resultados | Sort-Object UltimoLogin -Descending | Format-Table -Property `
        Nome, Login, @{Name="UltimoLogin"; Expression={$_.UltimoLogin.ToString("dd/MM/yyyy HH:mm")}}, `
        Status, Computador, DCOrigem -AutoSize -Wrap

    # Estatísticas
    Write-Host "`n--- ESTATÍSTICAS (somente usuários habilitados) ---" -ForegroundColor Cyan
    Write-Host "Usuários LOGADOS AGORA:              $($Resultados.Where({$_.Status -eq "LOGADO AGORA"}).Count)" -ForegroundColor Yellow

    # Exportar para CSV
    $Exportar = Read-Host "`nDeseja exportar para CSV? (S/N)"
    if ($Exportar -eq "S" -or $Exportar -eq "s") {
        $CaminhoCSV = "C:\Temp\Usuarios_Habilitados_Ativos_3Meses_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        if (!(Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" -Force }

        $Resultados | Export-Csv -Path $CaminhoCSV -NoTypeInformation -Encoding UTF8
        Write-Host "Arquivo exportado: $CaminhoCSV" -ForegroundColor Green
    }
} else {
    Write-Host "`nNenhum usuário HABILITADO encontrado com login nos últimos 3 meses!" -ForegroundColor Red
    Write-Host "Isso pode indicar:" -ForegroundColor Yellow
    Write-Host "  - Todos os usuários estão desabilitados ou são contas de serviço." -ForegroundColor Yellow
    Write-Host "  - Problemas na replicação do AD." -ForegroundColor Yellow
    Write-Host "  - Usuários estão usando contas locais (não do AD)." -ForegroundColor Yellow
}

Write-Host "`nScript finalizado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan
